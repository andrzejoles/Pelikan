import AppKit
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

    /// Kolumna z własnym widokiem komórki i tekstem (sortowanie po tekście).
    init<V: View>(_ title: String, id: String? = nil, text: @escaping (Row) -> String, @ViewBuilder content: @escaping (Row) -> V) {
        self.init(title: title, id: id, text: text, key: { text($0).sortKey }, content: { AnyView(content($0)) })
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

/// Tabela okna jako cel komend `table.*` (D214) i źródło SQL_ID dla „Raporty dla SQL_ID” (D217).
@MainActor
protocol FocusTable: TableHandle {
    /// Zapytanie z zaznaczonego wiersza (nil — tabela bez kolumny SQL albo bez zaznaczenia).
    var sqlTarget: SQLReportTarget? { get }
}

/// Tabela SwiftUI: jeden obiekt na widok (`@State`), odświeżany przy każdym rysowaniu — komenda wywołana później
/// (skrót, makro) widzi bieżące wiersze, a nie te z chwili zaznaczenia.
@MainActor
final class SwiftUITableHandle: FocusTable {
    private var provider: () -> TableContents = { TableContents(title: "", columns: [], rowCount: 0, cell: { _, _ in "" }, selectedRows: []) }
    private var target: () -> SQLReportTarget? = { nil }
    private var state: Binding<TableToolsState>?
    /// Widok tabeli z fokusem w chwili zapisu (NSTableView pod tabelą SwiftUI) — fokus w innej tabeli unieważnia ten cel.
    weak var responder: NSResponder?

    func update(contents: @escaping () -> TableContents, sqlTarget: @escaping () -> SQLReportTarget?, state: Binding<TableToolsState>) {
        provider = contents
        target = sqlTarget
        self.state = state
    }

    var contents: TableContents { provider() }
    var sqlTarget: SQLReportTarget? { target() }
    var filter: TableFilter {
        get { state?.wrappedValue.filter ?? TableFilter() }
        set { state?.wrappedValue.filter = newValue }
    }
    var markedColumns: [String] {
        get { state?.wrappedValue.markedColumns ?? [] }
        set { state?.wrappedValue.markedColumns = newValue }
    }
}

/// Tabela, której dotyczą komendy `table.*` i „Raporty dla SQL_ID”: tabela z menu w trakcie jej komendy, inaczej
/// tabela z fokusem w oknie bieżącym (AppKit — z narzędziami; SwiftUI — ostatnio używana, gdy nadal ma fokus).
@MainActor
final class TableFocus {
    static let shared = TableFocus()
    private weak var handle: (any FocusTable)?
    private var window: Int?
    /// Tabela, z której menu albo paska wywołano komendę — pierwszeństwo do końca tej komendy.
    private weak var explicit: (any FocusTable)?

    /// Okno czynności: okno z fokusem, a gdy fokus ma panel (paleta komend) — okno główne pod nim.
    static var contextWindow: NSWindow? {
        if let k = NSApp.keyWindow, !(k is NSPanel) { return k }
        return NSApp.mainWindow ?? NSApp.keyWindow
    }

    /// Tabela SwiftUI przejęła fokus albo zmieniła zaznaczenie.
    func note(_ h: SwiftUITableHandle) {
        handle = h
        window = Self.contextWindow?.windowNumber
        h.responder = Self.contextWindow?.firstResponder
    }

    /// Komenda `table.*` na tej tabeli (menu, pasek): działa na niej, nawet gdy fokus ma inna tabela.
    func perform(_ h: any FocusTable, _ id: String, _ args: [String: JSONValue]) {
        guard let ws = (NSApp.delegate as? AppDelegate)?.workspace else { return }
        explicit = h
        let task = ws.perform(CommandID(rawValue: id), CommandArguments(args))
        Task { @MainActor [weak self] in
            await task.value
            if let self, self.explicit === h { self.explicit = nil }
        }
    }

    func current() -> (any FocusTable)? {
        if let explicit { return explicit }
        let w = Self.contextWindow
        let responder = w?.firstResponder
        if responder is GridTableView { return nil }
        if let tv = responder as? NSTableView {
            if let tools = AppKitTableTools.tools(for: tv) { return tools }
            // Tabela SwiftUI: tylko ta, która zapisała się z tym widokiem; inna tabela AppKit — brak celu.
            guard let h = handle as? SwiftUITableHandle, h.responder === tv, window == w?.windowNumber else { return nil }
            return h
        }
        guard let handle, window == w?.windowNumber else { return nil }
        return handle
    }
}

/// Czynności tabel (D214): menu i pasek wywołują komendy `table.*` na tej tabeli.
@MainActor
enum TableActions {
    static func perform(_ handle: any FocusTable, _ id: String, _ args: [String: JSONValue] = [:]) {
        TableFocus.shared.perform(handle, id, args)
    }

    /// Numery wierszy widoku od 1 dla argumentu `rows`.
    static func rowsArgument(_ rows: [Int]) -> JSONValue { .string(rows.map { String($0 + 1) }.joined(separator: ",")) }

    /// Tytuł do nazwy pliku i arkusza: podany albo tytuł okna.
    static func title(_ given: String?) -> String {
        if let given, !given.isEmpty { return given }
        return NSApp.keyWindow?.title ?? L10n.tr("Tabela")
    }
}

/// Menu „Kopiuj” tabeli: komórka, wiersze, kolumny (pojedyncza i zaznaczone), cała tabela.
struct TableCopyMenu: View {
    /// Zawartość widoku policzona przy rysowaniu tabeli (menu jej nie przelicza).
    let contents: TableContents
    let handle: any FocusTable
    let marked: [String]
    /// Wiersze, do których odnosi się menu (zaznaczone albo kliknięty wiersz).
    let rows: [Int]

    var body: some View {
        if let r = rows.first {
            Menu(L10n.tr("Kopiuj komórkę")) {
                ForEach(contents.columns, id: \.id) { c in
                    let v = contents.cell(r, c.id)
                    Button("\(c.title): \(v.count > 40 ? String(v.prefix(40)) + "…" : v)") {
                        TableActions.perform(handle, "table.copyCell", ["row": .int(Int64(r + 1)), "column": .string(c.id)])
                    }
                }
            }
            Button(rows.count == 1 ? L10n.tr("Kopiuj wiersz") : L10n.tr("Kopiuj zaznaczone wiersze (\(rows.count))")) {
                TableActions.perform(handle, "table.copyRows", ["rows": TableActions.rowsArgument(rows)])
            }
        }
        Menu(L10n.tr("Kopiuj kolumnę")) {
            ForEach(contents.columns, id: \.id) { c in
                Button(c.title) { TableActions.perform(handle, "table.copyColumn", ["column": .string(c.id)]) }
            }
        }
        Menu(L10n.tr("Zaznacz kolumny do kopii")) {
            ForEach(contents.columns, id: \.id) { c in
                Toggle(c.title, isOn: Binding(get: { marked.contains(c.id) }, set: { _ in
                    TableActions.perform(handle, "table.markColumn", ["column": .string(c.id)])
                }))
            }
            if !marked.isEmpty {
                Divider()
                Button(L10n.tr("Odznacz wszystkie")) { TableActions.perform(handle, "table.clearMarkedColumns") }
            }
        }
        Button(L10n.tr("Kopiuj zaznaczone kolumny (\(marked.count))")) { TableActions.perform(handle, "table.copyMarkedColumns") }
            .disabled(marked.isEmpty)
        if rows.count > 0, !marked.isEmpty {
            Button(L10n.tr("Kopiuj zaznaczone kolumny zaznaczonych wierszy")) {
                TableActions.perform(handle, "table.copyMarkedColumns", ["rows": TableActions.rowsArgument(rows)])
            }
        }
        Button(L10n.tr("Kopiuj całą tabelę")) { TableActions.perform(handle, "table.copyAll") }
        Button(L10n.tr("Kopiuj nagłówki")) { TableActions.perform(handle, "table.copyHeaders") }
        Divider()
        Toggle(L10n.tr("Kopiuj z nagłówkiem"), isOn: Binding(get: { TableExport.copyHeader }, set: { _ in TableActions.perform(handle, "table.toggleCopyHeader") }))
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

/// Filtr po wartości komórki z menu wiersza.
struct TableValueFilterMenu: View {
    let columns: [(id: String, title: String)]
    let handle: any FocusTable
    let row: Int

    var body: some View {
        Menu(L10n.tr("Filtruj: tylko ta wartość")) {
            ForEach(columns, id: \.id) { c in Button(c.title) { filter(c.id, exclude: false) } }
        }
        Menu(L10n.tr("Filtruj: bez tej wartości")) {
            ForEach(columns, id: \.id) { c in Button(c.title) { filter(c.id, exclude: true) } }
        }
    }

    private func filter(_ column: String, exclude: Bool) {
        TableActions.perform(handle, "table.filterByValue", ["column": .string(column), "row": .int(Int64(row + 1)), "exclude": .bool(exclude)])
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
            TextField(L10n.tr("Filtr (LIKE: abc%, a_c)"), text: $state.filter.quick)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: compact ? 70 : 140, maxWidth: 220)
                .help(L10n.tr("Wiersze, w których dowolna kolumna pasuje do wzorca (bez wielkości liter; bez % i _ — fragment tekstu)."))
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
                TableCopyMenu(contents: contents, handle: handle, marked: state.markedColumns, rows: contents.selectedRows)
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
    /// Fokus w tej tabeli — cel komend `table.*` i raportów SQL (inna tabela okna go zastępuje).
    @FocusState private var focused: Bool
    @State private var handle = SwiftUITableHandle()
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

    private func viewRows() -> [Row] {
        let f = tools.filter.compiled()
        let ids = columns.map(\.id)
        let byID = Dictionary(columns.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let filtered = f.isEmpty ? rows : rows.filter { r in
            f.matches(all: ids) { id in byID[id].map { ($0.text(r), $0.key(r)) } ?? ("", .none) }
        }
        return filtered.sorted(by: sort)
    }

    /// Tabela ma kolumnę SQL_ID albo hash zapytania.
    private var hasSQLColumn: Bool { columns.contains { SQLIdentity.columnKind($0.title) != nil || SQLIdentity.columnKind($0.id) != nil } }

    /// Zapytanie z wiersza (kolumna SQL_ID, potem hash).
    private func sqlTarget(_ row: Row) -> SQLReportTarget? {
        let names = columns.map { SQLIdentity.columnKind($0.title) != nil ? $0.title : $0.id }
        return SQLIdentity.target(columns: names, values: columns.map { $0.text(row) })
            .map { SQLReportTarget(target: $0, origin: L10n.tr("zaznaczony wiersz tabeli"), connection: reportConnection) }
    }

    /// Cel raportów z zaznaczonego wiersza (nil — tabela bez kolumny SQL albo bez zaznaczenia).
    private func focusedTarget(_ shown: [Row], _ ids: Set<Row.ID>) -> SQLReportTarget? {
        guard hasSQLColumn else { return nil }
        return shown.first { ids.contains($0.id) }.flatMap(sqlTarget)
    }

    private func contents(_ shown: [Row]) -> TableContents {
        let byID = Dictionary(columns.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let selected = selection.ids
        return TableContents(title: TableActions.title(title), columns: columns.map { ($0.id, $0.title) }, rowCount: shown.count,
                             cell: { r, id in r < shown.count ? byID[id]?.text(shown[r]) ?? "" : "" },
                             selectedRows: selected.isEmpty ? [] : shown.indices.filter { selected.contains(shown[$0].id) })
    }

    var body: some View {
        let shown = viewRows()
        let contents = contents(shown)
        // Uchwyt widzi wiersze z tego rysowania (komendy wywołane później — bieżące dane, bez ponownego filtrowania).
        let view = self
        let _ = handle.update(contents: { view.contents(shown) }, sqlTarget: { view.focusedTarget(shown, view.selection.ids) }, state: $tools)
        VStack(spacing: 3) {
            TableToolsBar(contents: contents, handle: handle, state: $tools, total: rows.count)
            table(shown)
                .focused($focused)
                .contextMenu(forSelectionType: Row.ID.self) { ids in
                    rowMenuContent(ids, shown: shown, contents: contents)
                } primaryAction: { ids in
                    primaryAction?(ids)
                }
                .onCopyCommand {
                    let rows = contents.selectedRows
                    guard !rows.isEmpty else { return [] }
                    let c = TableExport.clipboard(contents.data(rows: rows), header: TableExport.copyHeader)
                    return [NSItemProvider(object: c.text as NSString)]
                }
        }
        .onChange(of: shown.map(\.id), initial: true) { _, ids in onViewRowsChange?(ids) }
        // Tabela z fokusem — cel komend `table.*` i „Raporty dla SQL_ID” ze wstążki, skrótu i palety (D214, D217).
        .onChange(of: selection.ids) {
            if focused { TableFocus.shared.note(handle) }
        }
        .onChange(of: focused) { _, now in
            if now { TableFocus.shared.note(handle) }
        }
        // Inny zestaw kolumn (np. inne zapytanie w tej samej tabeli) — filtr i sortowanie dotyczyły starych kolumn.
        .onChange(of: columns.map { $0.id + "\u{1}" + $0.title }) {
            tools = TableToolsState()
            sort = []
        }
    }

    /// Menu wiersza: raporty SQL, menu właściciela tabeli, kopia, filtr wartością, eksport.
    @ViewBuilder private func rowMenuContent(_ ids: Set<Row.ID>, shown: [Row], contents: TableContents) -> some View {
        let idx = shown.indices.filter { ids.contains(shown[$0].id) }
        if hasSQLColumn, let r = idx.first, let t = sqlTarget(shown[r]) {
            Button(L10n.tr("Raporty dla \(t.label)…")) { SQLReportLauncher.open(t) }
            Divider()
        }
        if let rowMenu, !ids.isEmpty {
            rowMenu(ids)
            Divider()
        }
        TableCopyMenu(contents: contents, handle: handle, marked: tools.markedColumns, rows: idx)
        if let r = idx.first {
            Divider()
            TableValueFilterMenu(columns: contents.columns, handle: handle, row: r)
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
