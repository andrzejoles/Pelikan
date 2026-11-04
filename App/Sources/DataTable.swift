import AppKit
import Combine
import PelikanLog
import PelikanWorkspace
import SwiftUI
import UniformTypeIdentifiers

/// Kolumna tabeli z narzędziami (D214): tytuł, tekst komórki (kopia, eksport, filtr), klucz sortowania (D212)
/// i opcjonalny własny widok komórki.
struct DataColumn<Row>: Identifiable {
    let id: String
    let title: String
    let text: (Row) -> String
    let key: (Row) -> SortKey
    let content: ((Row) -> AnyView)?
    var minWidth: CGFloat?
    var idealWidth: CGFloat?
    var maxWidth: CGFloat?
    /// Kolumna z danymi (kopia, eksport, filtr); kolumny czynności (przycisk, kosz) — nie.
    var exportable = true

    private init(title: String, id: String?, text: @escaping (Row) -> String, key: @escaping (Row) -> SortKey, content: ((Row) -> AnyView)?) {
        self.id = id ?? title
        self.title = title
        self.text = text
        self.key = key
        self.content = content
    }

    /// Kolumna z tekstem z wiersza, sortowana po nim (liczby w tekście — wg wartości).
    init(_ title: String, id: String? = nil, text: @escaping (Row) -> String) {
        self.init(title: title, id: id, text: text, key: { text($0).sortKey }, content: nil)
    }

    /// Kolumna sortowana po kluczu; tekst — podany albo z klucza.
    init<K: SortKeyConvertible>(_ title: String, id: String? = nil, sortKey: @escaping (Row) -> K, text: ((Row) -> String)? = nil) {
        let key: (Row) -> SortKey = { sortKey($0).sortKey }
        self.init(title: title, id: id, text: text ?? { key($0).text }, key: key, content: nil)
    }

    /// Kolumna z własnym widokiem komórki, sortowana po kluczu tekstowym albo całkowitym; tekst (kopia, eksport,
    /// filtr) — podany albo wartość klucza jako tekst (bez przejścia przez liczbę zmiennoprzecinkową klucza sortowania).
    init<K: TextualSortKey, V: View>(_ title: String, id: String? = nil, sortKey: @escaping (Row) -> K, text: ((Row) -> String)? = nil,
                                     @ViewBuilder content: @escaping (Row) -> V) {
        let key: (Row) -> SortKey = { sortKey($0).sortKey }
        self.init(title: title, id: id, text: text ?? { sortKey($0).cellText }, key: key, content: { AnyView(content($0)) })
    }

    /// Kolumna z własnym widokiem i kluczem liczbowym, datą albo wartością logiczną: tekst wymagany — taki jak w widoku
    /// (surowa wartość klucza różni się od pokazanej, np. 12.345678 wobec „12.35”).
    init<K: SortKeyConvertible, V: View>(_ title: String, id: String? = nil, sortKey: @escaping (Row) -> K, text: @escaping (Row) -> String,
                                         @ViewBuilder content: @escaping (Row) -> V) {
        let key: (Row) -> SortKey = { sortKey($0).sortKey }
        self.init(title: title, id: id, text: text, key: key, content: { AnyView(content($0)) })
    }

    /// Kolumna sortowana po kluczu, z tekstem pokazanym cyframi o stałej szerokości (liczby, czasy) — jedno
    /// formatowanie dla komórki, kopii, eksportu i filtra.
    static func digits<K: SortKeyConvertible>(_ title: String, id: String? = nil, sortKey: @escaping (Row) -> K, text: @escaping (Row) -> String) -> Self {
        let key: (Row) -> SortKey = { sortKey($0).sortKey }
        return Self(title: title, id: id, text: text, key: key, content: { AnyView(Text(text($0)).monospacedDigit()) })
    }

    /// Kolumna z własnym widokiem komórki i tekstem (sortowanie po tekście).
    init<V: View>(_ title: String, id: String? = nil, text: @escaping (Row) -> String, @ViewBuilder content: @escaping (Row) -> V) {
        self.init(title: title, id: id, text: text, key: { text($0).sortKey }, content: { AnyView(content($0)) })
    }

    /// Kolumna czynności (przycisk) — bez kopii, eksportu i filtra wartości.
    func action() -> Self {
        var c = self
        c.exportable = false
        return c
    }

    func width(_ w: CGFloat) -> Self { width(min: w, ideal: w, max: w) }

    func width(min: CGFloat? = nil, ideal: CGFloat? = nil, max: CGFloat? = nil) -> Self {
        var c = self
        c.minWidth = min
        c.idealWidth = ideal
        c.maxWidth = max
        return c
    }
}

/// Klucze, których tekst jest tym, co pokazuje komórka (tekst, liczby całkowite — dokładnie, także powyżej 2^53).
protocol TextualSortKey: SortKeyConvertible {
    var cellText: String { get }
}
extension String: TextualSortKey { var cellText: String { self } }
extension Substring: TextualSortKey { var cellText: String { String(self) } }
extension Int: TextualSortKey { var cellText: String { String(self) } }
extension Int64: TextualSortKey { var cellText: String { String(self) } }
extension Int32: TextualSortKey { var cellText: String { String(self) } }
extension UInt64: TextualSortKey { var cellText: String { String(self) } }
extension Binding: TextualSortKey where Value: TextualSortKey { var cellText: String { wrappedValue.cellText } }

/// Tekst pola wyboru w kopii, eksporcie i filtrze tabeli.
func checkText(_ on: Bool) -> String { on ? L10n.tr("tak") : L10n.tr("nie") }

@resultBuilder
enum DataColumnBuilder<Row> {
    static func buildExpression(_ c: DataColumn<Row>) -> [DataColumn<Row>] { [c] }
    static func buildExpression(_ c: [DataColumn<Row>]) -> [DataColumn<Row>] { c }
    static func buildBlock(_ parts: [DataColumn<Row>]...) -> [DataColumn<Row>] { parts.flatMap { $0 } }
    static func buildOptional(_ c: [DataColumn<Row>]?) -> [DataColumn<Row>] { c ?? [] }
    static func buildEither(first c: [DataColumn<Row>]) -> [DataColumn<Row>] { c }
    static func buildEither(second c: [DataColumn<Row>]) -> [DataColumn<Row>] { c }
    static func buildArray(_ parts: [[DataColumn<Row>]]) -> [DataColumn<Row>] { parts.flatMap { $0 } }
}

/// Zaznaczenie wierszy tabeli: brak, jeden wiersz albo wiele.
enum DataTableSelection<ID: Hashable> {
    case none
    case single(Binding<ID?>)
    case multi(Binding<Set<ID>>)

    var ids: Set<ID> {
        switch self {
        case .none: []
        case .single(let b): b.wrappedValue.map { [$0] } ?? []
        case .multi(let b): b.wrappedValue
        }
    }
}

/// Stan narzędzi tabeli: filtr, kolumny zaznaczone do kopii, otwarte okno filtra kolumn.
struct TableToolsState {
    var filter = TableFilter()
    var markedColumns: [String] = []
    var editingFilters = false
}

extension SQLReportTarget {
    /// Zapytanie z wiersza tabeli: kolumna SQL_ID, potem hash; nazwa kolumny — tytuł, a gdy nie pasuje — identyfikator
    /// (jedna reguła dla tabel SwiftUI i AppKit, menu wiersza i skrótu).
    static func fromTableRow(columns: [(id: String, title: String)], values: [String], connection: UUID?, origin: String) -> SQLReportTarget? {
        let names = columns.map { SQLIdentity.columnKind($0.title) != nil ? $0.title : $0.id }
        guard names.contains(where: { SQLIdentity.columnKind($0) != nil }) else { return nil }
        return SQLIdentity.target(columns: names, values: values).map { SQLReportTarget(target: $0, origin: origin, connection: connection) }
    }
}

/// Tabela okna jako cel komend `table.*` (D214) i źródło SQL_ID dla „Raporty dla SQL_ID” (D217).
@MainActor
protocol FocusTable: TableHandle {
    /// Zapytanie z zaznaczonego wiersza (nil — tabela bez kolumny SQL albo bez zaznaczenia).
    var sqlTarget: SQLReportTarget? { get }
    /// Okno tabeli (tytuł do nazwy pliku, arkusz zapisu eksportu).
    var window: NSWindow? { get }
    /// Zawartość i indeksy wierszy po identyfikatorach — liczone raz (migawka do komendy z menu).
    func snapshot() -> (contents: TableContents, indexes: ([AnyHashable]) -> [Int])
}

/// Migawka tabeli z chwili wyboru pozycji menu (D224): komenda z menu działa na tych wierszach, które widział
/// użytkownik — także gdy tabela odświeży się przed jej startem; widok liczony raz na czynność. Filtr i kolumny do kopii
/// zmieniają stan żywej tabeli.
@MainActor
final class FrozenTable: FocusTable {
    let contents: TableContents
    private let indexer: ([AnyHashable]) -> [Int]
    private weak var base: (any FocusTable)?
    weak var window: NSWindow?

    init(_ base: any FocusTable) {
        self.base = base
        window = base.window
        let snap = base.snapshot()
        contents = snap.contents
        indexer = snap.indexes
    }

    /// Tabela zamknięta przed startem komendy — komenda to zgłasza (zapis filtra nie miałby skutku).
    var isAvailable: Bool { base != nil }
    var sqlTarget: SQLReportTarget? { nil }
    func snapshot() -> (contents: TableContents, indexes: ([AnyHashable]) -> [Int]) { (contents, indexer) }

    var filter: TableFilter {
        get { base?.filter ?? TableFilter() }
        set { base?.filter = newValue }
    }
    var markedColumns: [String] {
        get { base?.markedColumns ?? [] }
        set { base?.markedColumns = newValue }
    }
    func indexes(of ids: [AnyHashable]) -> [Int] { indexer(ids) }

    /// Wiersze pozycji menu zniknęły (choćby część) — komenda to zgłasza.
    private(set) var menuRowsGone = false

    /// Indeksy wierszy menu; brak któregoś — `menuRowsGone`.
    func menuRows(_ ids: [AnyHashable]) -> [Int] {
        let rows = indexes(of: ids)
        if rows.count < Set(ids).count { menuRowsGone = true }
        return rows
    }

    /// Argument wierszy menu: brak — wiersze równe zaznaczeniu (komenda bierze zaznaczenie).
    func rowsArgument(_ ids: [AnyHashable]) -> [String: JSONValue] {
        let rows = menuRows(ids)
        return rows == contents.selectedRows ? [:] : ["rows": .string(rows.map { String($0 + 1) }.joined(separator: ","))]
    }

    /// Argument wiersza menu (numer od 1).
    func rowArgument(_ ids: [AnyHashable]) -> [String: JSONValue] {
        menuRows(ids).first.map { ["row": .int(Int64($0 + 1))] } ?? [:]
    }
}

/// Tabela SwiftUI: jeden obiekt na widok (`@State`), odświeżany przy każdym rysowaniu — komenda wywołana później
/// (skrót, makro) widzi bieżące wiersze. Domknięcia trzymają tylko wartości tabeli (wiersze, teksty kolumn,
/// zaznaczenie), nie widok — bez cyklu widok ↔ uchwyt.
@MainActor
final class SwiftUITableHandle: FocusTable, ObservableObject {
    /// Każde liczone osobno przy wywołaniu z bieżącymi wierszami widoku (filtr i sortowanie) — tylko to, czego trzeba.
    private var contentsNow: () -> TableContents = { TableContents(title: "", columns: [], rowCount: 0, cell: { _, _ in "" }, selectedRows: []) }
    private var targetNow: () -> SQLReportTarget? = { nil }
    private var snapshotNow: () -> (contents: TableContents, indexes: ([AnyHashable]) -> [Int]) = {
        (TableContents(title: "", columns: [], rowCount: 0, cell: { _, _ in "" }, selectedRows: []), { _ in [] })
    }
    private var state: Binding<TableToolsState>?
    /// Okno tabeli (sonda w tle tabeli); widok z fokusem rejestrowany przy zdobyciu fokusu.
    weak var window: NSWindow?

    /// `rows` — wiersze widoku liczone przy wywołaniu (bieżący filtr i sortowanie); zawartość i cel SQL z nich.
    func update<Row: Identifiable>(rows: @escaping () -> [Row], contents: @escaping ([Row]) -> TableContents,
                                   sqlTarget: @escaping ([Row]) -> SQLReportTarget?, state: Binding<TableToolsState>) {
        contentsNow = { contents(rows()) }
        targetNow = { sqlTarget(rows()) }
        snapshotNow = {
            let shown = rows()
            return (contents(shown), { ids in
                let set = Set(ids)
                return shown.indices.filter { set.contains(AnyHashable(shown[$0].id)) }
            })
        }
        self.state = state
    }

    var contents: TableContents { contentsNow() }
    var sqlTarget: SQLReportTarget? { targetNow() }
    func snapshot() -> (contents: TableContents, indexes: ([AnyHashable]) -> [Int]) { snapshotNow() }
    var filter: TableFilter {
        get { state?.wrappedValue.filter ?? TableFilter() }
        set { state?.wrappedValue.filter = newValue }
    }
    var markedColumns: [String] {
        get { state?.wrappedValue.markedColumns ?? [] }
        set { state?.wrappedValue.markedColumns = newValue }
    }

    /// Tabela zdobyła fokus: widok z fokusem okna to jej NSTableView — rejestracja bez szukania po geometrii.
    /// Fokus zdobyty, zanim sonda zapisała okno — rejestracja po jego zapisaniu.
    private var pendingFocus = false
    func focusedPending() {
        if pendingFocus { pendingFocus = false; focused() }
    }

    func focused() {
        guard window != nil else { pendingFocus = true; return }
        guard let window, let tv = window.firstResponder as? NSTableView, !(tv is GridTableView) else { return }
        TableFocus.registerSwiftUI(tv, self)
    }
}

/// Tabele okien po widoku `NSTableView` (D214, D217): cel komend `table.*` i „Raporty dla SQL_ID” to tabela z fokusem
/// w oknie bieżącym. Tabele AppKit rejestrują się przy utworzeniu, SwiftUI — przy zdobyciu fokusu.
@MainActor
enum TableFocus {
    private static let tables = NSMapTable<NSTableView, AnyObject>.weakToWeakObjects()
    /// Okno, nad którym otwarto paletę komend (jej czynności dotyczą tego okna).
    static weak var paletteHost: NSWindow?
    static weak var palette: NSWindow?

    static func register(_ table: NSTableView, _ handle: any FocusTable) { tables.setObject(handle, forKey: table) }

    /// Tabela SwiftUI z fokusem: nie nadpisuje tabeli AppKit z narzędziami (inny widok mógł mieć fokus w chwili
    /// zmiany stanu fokusu SwiftUI).
    static func registerSwiftUI(_ table: NSTableView, _ handle: SwiftUITableHandle) {
        if tables.object(forKey: table) is AppKitTableTools { return }
        tables.setObject(handle, forKey: table)
    }

    /// Okno czynności: okno z fokusem, a gdy fokus ma paleta komend — okno, nad którym ją otwarto.
    static var contextWindow: NSWindow? {
        if let k = NSApp.keyWindow, let palette, k === palette { return paletteHost ?? NSApp.mainWindow }
        return NSApp.keyWindow ?? NSApp.mainWindow
    }

    /// Tabela z fokusem w oknie bieżącym (siatka wyników SQL ma własne komendy `grid.*`). Bez skutków ubocznych —
    /// wołane przy sprawdzaniu menu i palety.
    static func current() -> (any FocusTable)? {
        guard let tv = contextWindow?.firstResponder as? NSTableView, !(tv is GridTableView) else { return nil }
        return tables.object(forKey: tv) as? any FocusTable
    }

    /// Okno tabeli komendy (migawka z menu albo tabela z fokusem) — arkusz zapisu eksportu.
    static func window(for table: any TableHandle) -> NSWindow? { (table as? any FocusTable)?.window }
}

/// Rejestracja tabeli SwiftUI jako celu komend `table.*`: okno (sonda w tle) i widok `NSTableView` przy zdobyciu
/// fokusu — wspólne dla `DataTable` i tabeli planu.
struct TableRegistration: ViewModifier {
    let handle: SwiftUITableHandle
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .onChange(of: focused, initial: true) { _, now in if now { handle.focused() } }
            .background(TableWindowProbe(handle: handle))
    }
}

extension View {
    func registersTable(_ handle: SwiftUITableHandle) -> some View { modifier(TableRegistration(handle: handle)) }
}

/// Sonda w tle tabeli SwiftUI: zapisuje okno tabeli w uchwycie (tytuł, arkusz zapisu) — bez szukania widoków.
struct TableWindowProbe: NSViewRepresentable {
    let handle: SwiftUITableHandle

    final class Probe: NSView {
        weak var handle: SwiftUITableHandle?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            handle?.window = window
            handle?.focusedPending()
        }
    }

    func makeNSView(context: Context) -> Probe {
        let p = Probe()
        p.handle = handle
        return p
    }

    func updateNSView(_ p: Probe, context: Context) {
        p.handle = handle
        if handle.window == nil { handle.window = p.window }
    }
}

/// Czynności tabel (D214): menu i pasek wywołują komendy `table.*` ze wskazaniem tej tabeli (argument `table`) —
/// działają na niej niezależnie od fokusu i okna kluczowego.
@MainActor
enum TableActions {
    /// Komenda na wierszach z menu: na migawce tabeli z chwili wyboru pozycji (`args` z tej migawki — wiersze po
    /// identyfikatorach). Cel przekazany jako `CommandContext.target`, poza argumentami (nie trafia do makr).
    static func performOnRows(_ handle: any FocusTable, _ id: String, _ args: (FrozenTable) -> [String: JSONValue]) {
        // Menu kontekstowe tabeli SwiftUI przekazuje migawkę z chwili otwarcia (etykiety i czynność — te same dane).
        let frozen = (handle as? FrozenTable) ?? FrozenTable(handle)
        let a = args(frozen)
        (NSApp.delegate as? AppDelegate)?.workspace.perform(CommandID(rawValue: id), CommandArguments(a), target: frozen)
    }

    /// Komenda na tej tabeli bez czytania wierszy w chwili kliknięcia (filtr, kolumny do kopii, cała tabela, eksport) —
    /// bez migawki.
    static func perform(_ handle: any FocusTable, _ id: String, _ args: [String: JSONValue] = [:]) {
        (NSApp.delegate as? AppDelegate)?.workspace.perform(CommandID(rawValue: id), CommandArguments(args), target: handle)
    }

    /// Tytuł do nazwy pliku i arkusza: podany albo tytuł okna tabeli.
    static func title(_ given: String?, window: NSWindow?) -> String {
        if let given, !given.isEmpty { return given }
        if let t = window?.title, !t.isEmpty { return t }
        return L10n.tr("Tabela")
    }
}

/// Wiersze, do których odnosi się menu tabeli: z menu kontekstowego (identyfikatory — indeksy liczone przy wyborze
/// pozycji) albo zaznaczone w chwili komendy (pasek).
enum TableMenuRows {
    case context(ids: [AnyHashable], count: Int, first: Int)
    case selection

    /// Menu kontekstowe: wiersze o identyfikatorach `ids` w wierszach widoku; klik poza wierszami — jak pasek.
    static func from<Row: Identifiable>(_ ids: Set<Row.ID>, shown: [Row]) -> TableMenuRows {
        let idx = shown.indices.filter { ids.contains(shown[$0].id) }
        return idx.isEmpty ? .selection : .context(ids: idx.map { AnyHashable(shown[$0].id) }, count: idx.count, first: idx[0])
    }
}

/// Menu „Kopiuj” tabeli: komórka, wiersze, kolumny (pojedyncza i zaznaczone), cała tabela.
struct TableCopyMenu: View {
    /// Zawartość widoku policzona przy rysowaniu tabeli — tylko do etykiet menu.
    let contents: TableContents
    let handle: any FocusTable
    let marked: [String]
    let rows: TableMenuRows

    private func run(_ id: String, _ args: [String: JSONValue] = [:]) { TableActions.perform(handle, id, args) }

    /// Komenda z wierszami menu kontekstowego (indeksy z migawki w chwili wyboru pozycji).
    private func runRows(_ id: String, _ extra: [String: JSONValue] = [:], cell: Bool = false) {
        TableActions.performOnRows(handle, id) { f in
            guard case .context(let ids, _, _) = rows else { return extra }
            return extra.merging(cell ? f.rowArgument(ids) : f.rowsArgument(ids)) { a, _ in a }
        }
    }

    var body: some View {
        switch rows {
        case .context(_, let count, let first):
            Menu(L10n.tr("Kopiuj komórkę")) {
                ForEach(contents.columns, id: \.id) { c in
                    let v = first < contents.rowCount ? contents.cell(first, c.id) : ""
                    Button("\(c.title): \(v.count > 40 ? String(v.prefix(40)) + "…" : v)") { runRows("table.copyCell", ["column": .string(c.id)], cell: true) }
                }
            }
            Button(count == 1 ? L10n.tr("Kopiuj wiersz") : L10n.tr("Kopiuj zaznaczone wiersze (\(count))")) { runRows("table.copyRows") }
        case .selection:
            Menu(L10n.tr("Kopiuj komórkę")) {
                ForEach(contents.columns, id: \.id) { c in Button(c.title) { run("table.copyCell", ["column": .string(c.id)]) } }
            }
            .disabled(contents.selectedRows.isEmpty)
            Button(L10n.tr("Kopiuj zaznaczone wiersze")) { run("table.copyRows") }
                .disabled(contents.selectedRows.isEmpty)
        }
        Menu(L10n.tr("Kopiuj kolumnę")) {
            ForEach(contents.columns, id: \.id) { c in Button(c.title) { run("table.copyColumn", ["column": .string(c.id)]) } }
        }
        Menu(L10n.tr("Zaznacz kolumny do kopii")) {
            ForEach(contents.columns, id: \.id) { c in
                Toggle(c.title, isOn: Binding(get: { marked.contains(c.id) }, set: { _ in run("table.markColumn", ["column": .string(c.id)]) }))
            }
            if !marked.isEmpty {
                Divider()
                Button(L10n.tr("Odznacz wszystkie")) { run("table.clearMarkedColumns") }
            }
        }
        Button(L10n.tr("Kopiuj zaznaczone kolumny (\(marked.count))")) { run("table.copyMarkedColumns") }
            .disabled(marked.isEmpty)
        if !marked.isEmpty {
            switch rows {
            case .context(let ids, _, _):
                Button(L10n.tr("Kopiuj zaznaczone kolumny zaznaczonych wierszy")) {
                    // Zawsze wiersze menu (bez argumentu komenda kopiowałaby wszystkie).
                    TableActions.performOnRows(handle, "table.copyMarkedColumns") { f in
                        ["rows": .string(f.menuRows(ids).map { String($0 + 1) }.joined(separator: ","))]
                    }
                }
            case .selection:
                Button(L10n.tr("Kopiuj zaznaczone kolumny zaznaczonych wierszy")) { run("table.copyMarkedColumns", ["selected": .bool(true)]) }
                    .disabled(contents.selectedRows.isEmpty)
            }
        }
        Button(L10n.tr("Kopiuj całą tabelę")) { run("table.copyAll") }
        Button(L10n.tr("Kopiuj nagłówki")) { run("table.copyHeaders") }
        Divider()
        Toggle(L10n.tr("Kopiuj z nagłówkiem"), isOn: Binding(get: { TableExport.copyHeader }, set: { _ in run("table.toggleCopyHeader") }))
    }
}

/// Menu „Eksportuj” tabeli (cała tabela po filtrze, w kolejności widoku).
struct TableExportMenu: View {
    let handle: any FocusTable

    var body: some View {
        ForEach(TableExport.formats, id: \.self) { f in
            Button(f.displayName + "…") { TableActions.perform(handle, "table.export", ["format": .string(f.rawValue)]) }
        }
    }
}

/// Filtr po wartości komórki z menu wiersza (wiersz po identyfikatorze — indeks liczony przy wyborze pozycji).
struct TableValueFilterMenu: View {
    let columns: [(id: String, title: String)]
    let handle: any FocusTable
    let rowID: AnyHashable

    var body: some View {
        Menu(L10n.tr("Filtruj: tylko ta wartość")) {
            ForEach(columns, id: \.id) { c in Button(c.title) { filter(c.id, exclude: false) } }
        }
        Menu(L10n.tr("Filtruj: bez tej wartości")) {
            ForEach(columns, id: \.id) { c in Button(c.title) { filter(c.id, exclude: true) } }
        }
    }

    private func filter(_ column: String, exclude: Bool) {
        TableActions.performOnRows(handle, "table.filterByValue") { f in
            f.rowArgument([rowID]).merging(["column": .string(column), "exclude": .bool(exclude)]) { a, _ in a }
        }
    }
}

/// Pasek narzędzi nad tabelą: szybki filtr, filtr kolumn, liczba wierszy, Kopiuj, Eksportuj. W wąskim panelu — same
/// ikony (pełne nazwy w podpowiedziach).
struct TableToolsBar: View {
    let contents: TableContents
    let handle: any FocusTable
    @Binding var state: TableToolsState
    let total: Int

    var body: some View {
        ViewThatFits(in: .horizontal) {
            bar(compact: false)
            bar(compact: true)
        }
        .controlSize(.small)
        .font(.uiSecondary)
    }

    private var activeColumns: Int { state.filter.columns.values.filter { ValueFilter.parse($0) != nil }.count }

    @ViewBuilder private func bar(compact: Bool) -> some View {
        HStack(spacing: 6) {
            if !compact { Image(systemName: "line.3.horizontal.decrease.circle").foregroundStyle(.secondary) }
            TextField(L10n.tr("Filtr (fragment; LIKE: abc%)"), text: $state.filter.quick)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: compact ? 70 : 140, maxWidth: 220)
                .help(L10n.tr("Wiersze, w których dowolna kolumna zawiera tekst (bez wielkości liter; _ — jeden dowolny znak). Z % — wzorzec LIKE całej wartości (abc% — zaczyna się od abc)."))
            Button {
                state.editingFilters.toggle()
            } label: {
                let icon = activeColumns > 0 ? "line.3.horizontal.decrease.circle.fill" : "slider.horizontal.3"
                if compact {
                    Image(systemName: icon)
                } else {
                    Label(activeColumns > 0 ? L10n.tr("Filtr kolumn (\(activeColumns))") : L10n.tr("Filtr kolumn…"), systemImage: icon)
                }
            }
            .help(L10n.tr("Filtr wartości kolumn: wzorzec LIKE, porównanie liczb i dat"))
            .popover(isPresented: $state.editingFilters, arrowEdge: .bottom) {
                TableFilterEditor(handle: handle, columns: contents.columns, state: $state)
            }
            if state.filter.isActive {
                Button { TableActions.perform(handle, "table.clearFilter") } label: {
                    if compact { Image(systemName: "xmark.circle") } else { Text(L10n.tr("Wyczyść filtr")) }
                }
                .help(L10n.tr("Wyczyść filtr"))
            }
            Spacer(minLength: 2)
            Text(state.filter.isActive ? (compact ? "\(contents.rowCount)/\(total)" : L10n.tr("Wierszy: \(contents.rowCount) z \(total)"))
                 : (compact ? "\(total)" : L10n.tr("Wierszy: \(total)")))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
            Menu {
                TableCopyMenu(contents: contents, handle: handle, marked: state.markedColumns, rows: .selection)
            } label: {
                if compact { Image(systemName: "doc.on.doc") } else { Text(L10n.tr("Kopiuj")) }
            }
            .menuIndicator(compact ? .hidden : .visible)
            .fixedSize()
            .help(L10n.tr("Kopiuj"))
            Menu {
                TableExportMenu(handle: handle)
            } label: {
                if compact { Image(systemName: "square.and.arrow.up") } else { Text(L10n.tr("Eksportuj")) }
            }
            .menuIndicator(compact ? .hidden : .visible)
            .fixedSize()
            .help(L10n.tr("Eksportuj"))
        }
    }
}

/// Okno filtra kolumn: wzorzec albo warunek dla każdej kolumny.
struct TableFilterEditor: View {
    let handle: any FocusTable
    let columns: [(id: String, title: String)]
    @Binding var state: TableToolsState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("Filtr kolumn")).font(.headline)
            Text(L10n.tr("Tekst: wzorzec LIKE bez wielkości liter (% — dowolny ciąg, _ — jeden znak; bez nich — równość), not like …. Liczby i daty: = 5, >= 6, <> 0, between 3 and 4, = 2026-10-03 (cały dzień), > 2026-10-03 12:00. Puste: is null, is not null."))
                .font(.uiSecondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 380, alignment: .leading)
            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                    ForEach(columns, id: \.id) { c in
                        GridRow {
                            Text(c.title).lineLimit(1).frame(maxWidth: 150, alignment: .leading)
                            let text = Binding(get: { state.filter.columns[c.id] ?? "" }, set: { state.filter.columns[c.id] = $0.isEmpty ? nil : $0 })
                            TextField("", text: text)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 210)
                                .foregroundStyle(text.wrappedValue.isEmpty || ValueFilter.parse(text.wrappedValue) != nil ? Color.primary : Color.red)
                        }
                    }
                }
            }
            .frame(maxHeight: 360)
            HStack {
                Button(L10n.tr("Wyczyść filtr")) { TableActions.perform(handle, "table.clearFilter") }
                Spacer()
                Button(L10n.tr("Zamknij")) { state.editingFilters = false }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
    }
}

/// Tabela SwiftUI z sortowaniem (D212), filtrem wartości kolumn, kopiowaniem i eksportem (D214).
struct DataTable<Row: Identifiable>: View {
    let title: String?
    let rows: [Row]
    let columns: [DataColumn<Row>]
    let selection: DataTableSelection<Row.ID>
    let rowMenu: ((Set<Row.ID>) -> AnyView)?
    let primaryAction: ((Set<Row.ID>) -> Void)?
    /// Zmiana wierszy widoku (po filtrze i sortowaniu) — np. nawigacja strzałkami w kolejności widoku.
    let onViewRowsChange: (([Row.ID]) -> Void)?
    @State private var sort: [ColumnSort<Row>] = []
    @State private var tools = TableToolsState()
    /// Uchwyt tabeli dla komend `table.*` i raportów SQL (rejestrowany z widokiem NSTableView przy zdobyciu fokusu).
    @StateObject private var handle = SwiftUITableHandle()
    /// Połączenie tabeli narzędzia — raporty SQL z wiersza z kolumną SQL_ID/hash (D217).
    @Environment(\.reportConnection) private var reportConnection

    init(_ rows: [Row], title: String? = nil, selection: DataTableSelection<Row.ID> = .none,
         rowMenu: ((Set<Row.ID>) -> AnyView)? = nil, primaryAction: ((Set<Row.ID>) -> Void)? = nil,
         onViewRowsChange: (([Row.ID]) -> Void)? = nil,
         @DataColumnBuilder<Row> columns: () -> [DataColumn<Row>]) {
        self.title = title
        self.rows = rows
        self.selection = selection
        self.rowMenu = rowMenu
        self.primaryAction = primaryAction
        self.onViewRowsChange = onViewRowsChange
        self.columns = columns()
    }

    private func viewRows() -> [Row] { Self.viewRows(rows, columns: columns, filter: tools.filter, sort: sort) }

    /// Wiersze widoku: filtr i sortowanie (także dla komend wywołanych przed przerysowaniem — makro, kilka komend z rzędu).
    static func viewRows(_ rows: [Row], columns: [DataColumn<Row>], filter: TableFilter, sort: [ColumnSort<Row>]) -> [Row] {
        let f = filter.compiled()
        let ids = columns.map(\.id)
        let byID = Dictionary(columns.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let filtered = f.isEmpty ? rows : rows.filter { r in
            f.matches(all: ids) { id in byID[id].map { ($0.text(r), $0.key(r)) } ?? ("", .none) }
        }
        return filtered.sorted(by: sort)
    }

    /// Wartości tabeli dla uchwytu (bez widoku — uchwyt w `@State` nie może trzymać widoku, który trzyma uchwyt).
    struct Snapshot {
        let texts: [(id: String, title: String, text: (Row) -> String)]
        let title: String?
        let connection: UUID?
        let selected: () -> Set<Row.ID>
        weak var handle: SwiftUITableHandle?

        func contents(_ shown: [Row]) -> TableContents {
            let byID = Dictionary(texts.map { ($0.id, $0.text) }, uniquingKeysWith: { a, _ in a })
            let selected = selected()
            return TableContents(title: TableActions.title(title, window: handle?.window), columns: texts.map { ($0.id, $0.title) },
                                 rowCount: shown.count, cell: { r, id in r < shown.count ? byID[id]?(shown[r]) ?? "" : "" },
                                 selectedRows: selected.isEmpty ? [] : shown.indices.filter { selected.contains(shown[$0].id) })
        }

        /// Zapytanie z wiersza (kolumna SQL_ID, potem hash) — menu wiersza, skrót, wstążka (jedna reguła).
        func sqlTarget(row: Row) -> SQLReportTarget? {
            SQLReportTarget.fromTableRow(columns: texts.map { ($0.id, $0.title) }, values: texts.map { $0.text(row) },
                                         connection: connection, origin: L10n.tr("zaznaczony wiersz tabeli"))
        }

        func sqlTarget(_ shown: [Row]) -> SQLReportTarget? {
            let selected = selected()
            return shown.first(where: { selected.contains($0.id) }).flatMap(sqlTarget(row:))
        }
    }

    static func snapshot(columns: [DataColumn<Row>], title: String?, connection: UUID?, selection: DataTableSelection<Row.ID>,
                         handle: SwiftUITableHandle) -> Snapshot {
        Snapshot(texts: columns.filter(\.exportable).map { ($0.id, $0.title, $0.text) }, title: title, connection: connection,
                 selected: { selection.ids }, handle: handle)
    }

    var body: some View {
        let shown = viewRows()
        let snapshot = Self.snapshot(columns: columns, title: title, connection: reportConnection, selection: selection, handle: handle)
        let contents = snapshot.contents(shown)
        // Komendy liczą wiersze widoku przy wywołaniu z bieżącego filtra i sortowania (stan narzędzi mógł się zmienić bez
        // przerysowania — makro, kilka komend z rzędu). Domknięcia trzymają wartości tabeli, nie widok.
        let (all, cols, toolsState, sortState) = (rows, columns, $tools, $sort)
        let _ = handle.update(rows: { Self.viewRows(all, columns: cols, filter: toolsState.wrappedValue.filter, sort: sortState.wrappedValue) },
                              contents: snapshot.contents, sqlTarget: snapshot.sqlTarget, state: $tools)
        VStack(spacing: 3) {
            TableToolsBar(contents: contents, handle: handle, state: $tools, total: rows.count)
            table(shown)
                .registersTable(handle)
                .contextMenu(forSelectionType: Row.ID.self) { ids in
                    rowMenuContent(ids, shown: shown, contents: contents, snapshot: snapshot)
                } primaryAction: { ids in
                    primaryAction?(ids)
                }
                // ⌘C — systemowe „Kopiuj” (Edycja › Kopiuj, jak w polach tekstowych i siatce): zawartość od razu, w tej
                // samej chwili; menu tabeli i paleta mają komendę „Kopiuj wiersze tabeli”.
                .onCopyCommand {
                    let rows = contents.selectedRows
                    guard !rows.isEmpty else { return [] }
                    let c = TableExport.clipboard(contents.data(rows: rows), header: TableExport.copyHeader)
                    return [NSItemProvider(object: c.text as NSString)]
                }
        }
        .onChange(of: shown.map(\.id), initial: true) { _, ids in onViewRowsChange?(ids) }
        // Inny zestaw kolumn (np. inne zapytanie w tej samej tabeli) — filtr i sortowanie dotyczyły starych kolumn.
        .onChange(of: columns.map { $0.id + "\u{1}" + $0.title }) {
            tools = TableToolsState()
            sort = []
        }
    }

    /// Menu wiersza: raporty SQL, menu właściciela tabeli, kopia, filtr wartością, eksport.
    @ViewBuilder private func rowMenuContent(_ ids: Set<Row.ID>, shown: [Row], contents: TableContents, snapshot: Snapshot) -> some View {
        let idx = shown.indices.filter { ids.contains(shown[$0].id) }
        if let r = idx.first, let t = snapshot.sqlTarget(row: shown[r]) {
            Button(L10n.tr("Raporty dla \(t.label)…")) { SQLReportLauncher.open(t) }
            Divider()
        }
        if let rowMenu, !ids.isEmpty {
            rowMenu(ids)
            Divider()
        }
        // Migawka z chwili otwarcia menu: etykiety („Kolumna: wartość”) i czynność na tych samych danych, także gdy tabela
        // odświeży się przed wyborem pozycji. Klik poza wierszami — menu jak na pasku (zaznaczenie w chwili komendy).
        let frozen = FrozenTable(handle)
        TableCopyMenu(contents: frozen.contents, handle: frozen, marked: tools.markedColumns, rows: .from(ids, shown: shown))
        if let r = idx.first {
            Divider()
            TableValueFilterMenu(columns: frozen.contents.columns, handle: frozen, rowID: AnyHashable(shown[r].id))
        }
        if tools.filter.isActive { Button(L10n.tr("Wyczyść filtr")) { TableActions.perform(handle, "table.clearFilter") } }
        Divider()
        Menu(L10n.tr("Eksportuj")) { TableExportMenu(handle: handle) }
    }

    @ViewBuilder private func table(_ shown: [Row]) -> some View {
        switch selection {
        case .none: Table(shown, sortOrder: $sort) { columnContent }
        case .single(let b): Table(shown, selection: b, sortOrder: $sort) { columnContent }
        case .multi(let b): Table(shown, selection: b, sortOrder: $sort) { columnContent }
        }
    }

    @TableColumnBuilder<Row, ColumnSort<Row>> private var columnContent: some TableColumnContent<Row, ColumnSort<Row>> {
        TableColumnForEach(columns) { c in
            TableColumn(c.title, sortUsing: ColumnSort(c.id, c.key)) { (r: Row) in
                if let content = c.content { content(r) } else { Text(c.text(r)).lineLimit(1) }
            }
            .width(min: c.minWidth, ideal: c.idealWidth, max: c.maxWidth)
        }
    }
}

extension Binding where Value: Identifiable {
    /// Wiązania wierszy edytowanej tablicy po identyfikatorze (tabela z polami edycji): kolejność widoku może się
    /// różnić od kolejności w tablicy, a zmiana wiersza trafia do elementu o tym samym identyfikatorze.
    @MainActor
    static func rows(_ base: Binding<[Value]>) -> [Binding<Value>] {
        base.wrappedValue.map { item in
            let id = item.id
            return Binding<Value>(get: { base.wrappedValue.first { $0.id == id } ?? item },
                                 set: { v in if let i = base.wrappedValue.firstIndex(where: { $0.id == id }) { base.wrappedValue[i] = v } })
        }
    }
}
