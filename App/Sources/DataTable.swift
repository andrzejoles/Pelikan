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

    /// Kolumna z własnym widokiem komórki, sortowana po kluczu; tekst — podany albo z klucza.
    init<K: SortKeyConvertible, V: View>(_ title: String, id: String? = nil, sortKey: @escaping (Row) -> K, text: ((Row) -> String)? = nil,
                                         @ViewBuilder content: @escaping (Row) -> V) {
        let key: (Row) -> SortKey = { sortKey($0).sortKey }
        self.init(title: title, id: id, text: text ?? { key($0).text }, key: key, content: { AnyView(content($0)) })
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

/// Wiersze i kolumny tabeli do kopii i eksportu (tekst komórek w kolejności widoku).
@MainActor
struct TableContents {
    let title: String
    let columns: [(id: String, title: String)]
    /// Wiersze widoku (po filtrze i sortowaniu); `cell(wiersz, kolumna)` — tekst komórki.
    let rowCount: Int
    let cell: (Int, String) -> String
    /// Indeksy wierszy widoku zaznaczonych w tabeli.
    let selectedRows: [Int]

    func data(rows: [Int], columns ids: [String]? = nil) -> ExportData {
        let cols = ids.map { set in columns.filter { set.contains($0.id) } } ?? columns
        return TableExport.data(title: title, columns: cols.map(\.title), rows: rows.map { r in cols.map { cell(r, $0.id) } })
    }

    var all: [Int] { Array(0..<rowCount) }
}

/// Czynności kopiowania i eksportu (D214) — wspólne dla tabel SwiftUI i AppKit.
@MainActor
enum TableActions {
    static func copy(_ data: ExportData, header: Bool) {
        let c = TableExport.clipboard(data, header: header)
        put(c.text, html: c.html)
    }

    static func put(_ text: String, html: String? = nil) {
        if let ui = (NSApp.delegate as? AppDelegate) {
            ui.copyToClipboard(text, html: html)
        } else {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
            if let html { pb.setString(html, forType: .html) }
        }
    }

    static func export(_ format: ExportFormat, _ data: ExportData) {
        if AppDelegate.scriptSkipsDialog("tableExport") { return }
        let panel = NSSavePanel()
        let name = data.title.isEmpty ? L10n.tr("Tabela") : data.title
        panel.nameFieldStringValue = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") + "." + format.fileExtension
        panel.allowedContentTypes = [UTType(filenameExtension: format.fileExtension) ?? .data]
        panel.canCreateDirectories = true
        let bytes = TableExport.file(format, data)
        let write: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try bytes.write(to: url, options: .atomic)
                Log.tools.info("Eksport tabeli: \(format.rawValue, privacy: .public), wierszy \(data.rows.count, privacy: .public)")
            } catch {
                NSAlert(error: error).runModal()
            }
        }
        if let w = NSApp.keyWindow { panel.beginSheetModal(for: w, completionHandler: write) } else { write(panel.runModal()) }
    }

    /// Tytuł do nazwy pliku i arkusza: podany albo tytuł okna.
    static func title(_ given: String?) -> String {
        if let given, !given.isEmpty { return given }
        return NSApp.keyWindow?.title ?? L10n.tr("Tabela")
    }

    static var copyHeader: Bool {
        get { UserDefaults.standard.object(forKey: "tableCopyHeader") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "tableCopyHeader") }
    }
}

/// Menu „Kopiuj” tabeli: komórka, wiersze, kolumny (pojedyncza i zaznaczone), cała tabela.
struct TableCopyMenu: View {
    let contents: TableContents
    @Binding var state: TableToolsState
    /// Wiersze, do których odnosi się menu (zaznaczone albo kliknięty wiersz).
    let rows: [Int]

    var body: some View {
        let header = TableActions.copyHeader
        if let r = rows.first {
            Menu(L10n.tr("Kopiuj komórkę")) {
                ForEach(contents.columns, id: \.id) { c in
                    let v = contents.cell(r, c.id)
                    Button("\(c.title): \(v.count > 40 ? String(v.prefix(40)) + "…" : v)") { TableActions.put(v) }
                }
            }
            Button(rows.count == 1 ? L10n.tr("Kopiuj wiersz") : L10n.tr("Kopiuj zaznaczone wiersze (\(rows.count))")) {
                TableActions.copy(contents.data(rows: rows), header: header)
            }
        }
        Menu(L10n.tr("Kopiuj kolumnę")) {
            ForEach(contents.columns, id: \.id) { c in
                Button(c.title) { TableActions.copy(contents.data(rows: contents.all, columns: [c.id]), header: header) }
            }
        }
        Menu(L10n.tr("Zaznacz kolumny do kopii")) {
            ForEach(contents.columns, id: \.id) { c in
                Toggle(c.title, isOn: Binding(get: { state.markedColumns.contains(c.id) }, set: { on in
                    state.markedColumns.removeAll { $0 == c.id }
                    if on { state.markedColumns.append(c.id) }
                }))
            }
            if !state.markedColumns.isEmpty {
                Divider()
                Button(L10n.tr("Odznacz wszystkie")) { state.markedColumns = [] }
            }
        }
        Button(L10n.tr("Kopiuj zaznaczone kolumny (\(state.markedColumns.count))")) {
            TableActions.copy(contents.data(rows: contents.all, columns: state.markedColumns), header: header)
        }
        .disabled(state.markedColumns.isEmpty)
        if rows.count > 0, !state.markedColumns.isEmpty {
            Button(L10n.tr("Kopiuj zaznaczone kolumny zaznaczonych wierszy")) {
                TableActions.copy(contents.data(rows: rows, columns: state.markedColumns), header: header)
            }
        }
        Button(L10n.tr("Kopiuj całą tabelę")) { TableActions.copy(contents.data(rows: contents.all), header: header) }
        Button(L10n.tr("Kopiuj nagłówki")) { TableActions.put(contents.columns.map(\.title).joined(separator: "\t")) }
        Divider()
        Toggle(L10n.tr("Kopiuj z nagłówkiem"), isOn: Binding(get: { TableActions.copyHeader }, set: { TableActions.copyHeader = $0 }))
    }
}

/// Menu „Eksportuj” tabeli (cała tabela po filtrze, w kolejności widoku).
struct TableExportMenu: View {
    let contents: TableContents

    var body: some View {
        ForEach(TableExport.formats, id: \.self) { f in
            Button(f.displayName + "…") { TableActions.export(f, contents.data(rows: contents.all)) }
        }
    }
}

/// Filtr po wartości komórki z menu wiersza.
struct TableValueFilterMenu: View {
    let contents: TableContents
    @Binding var state: TableToolsState
    let row: Int

    var body: some View {
        Menu(L10n.tr("Filtruj: tylko ta wartość")) {
            ForEach(contents.columns, id: \.id) { c in
                Button(c.title) { state.filter.columns[c.id] = Self.condition(contents.cell(row, c.id), exclude: false) }
            }
        }
        Menu(L10n.tr("Filtruj: bez tej wartości")) {
            ForEach(contents.columns, id: \.id) { c in
                Button(c.title) { state.filter.columns[c.id] = Self.condition(contents.cell(row, c.id), exclude: true) }
            }
        }
    }

    static func condition(_ value: String, exclude: Bool) -> String {
        if value.isEmpty { return exclude ? "is not null" : "is null" }
        let v = value.contains("'") || value.hasPrefix(" ") || value.hasSuffix(" ") ? "'" + value.replacingOccurrences(of: "'", with: "''") + "'" : value
        return (exclude ? "<> " : "= ") + v
    }
}

/// Pasek narzędzi nad tabelą: szybki filtr, filtr kolumn, liczba wierszy, Kopiuj, Eksportuj. W wąskim panelu — same
/// ikony (pełne nazwy w podpowiedziach).
struct TableToolsBar: View {
    let contents: TableContents
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
                TableFilterEditor(columns: contents.columns, state: $state)
            }
            if state.filter.isActive {
                Button { state.filter = TableFilter() } label: {
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
                TableCopyMenu(contents: contents, state: $state, rows: contents.selectedRows)
            } label: {
                if compact { Image(systemName: "doc.on.doc") } else { Text(L10n.tr("Kopiuj")) }
            }
            .menuIndicator(compact ? .hidden : .visible)
            .fixedSize()
            .help(L10n.tr("Kopiuj"))
            Menu {
                TableExportMenu(contents: contents)
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
                Button(L10n.tr("Wyczyść filtr")) { state.filter = TableFilter() }
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
        VStack(spacing: 3) {
            TableToolsBar(contents: contents, state: $tools, total: rows.count)
            table(shown)
                .contextMenu(forSelectionType: Row.ID.self) { ids in
                    let idx = shown.indices.filter { ids.contains(shown[$0].id) }
                    if let rowMenu, !ids.isEmpty {
                        rowMenu(ids)
                        Divider()
                    }
                    TableCopyMenu(contents: contents, state: $tools, rows: idx)
                    if let r = idx.first {
                        Divider()
                        TableValueFilterMenu(contents: contents, state: $tools, row: r)
                    }
                    if tools.filter.isActive { Button(L10n.tr("Wyczyść filtr")) { tools.filter = TableFilter() } }
                    Divider()
                    Menu(L10n.tr("Eksportuj")) { TableExportMenu(contents: contents) }
                } primaryAction: { ids in
                    primaryAction?(ids)
                }
                .onCopyCommand {
                    let rows = contents.selectedRows
                    guard !rows.isEmpty else { return [] }
                    let c = TableExport.clipboard(contents.data(rows: rows), header: TableActions.copyHeader)
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
