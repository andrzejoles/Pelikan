import AppKit
import PelikanWorkspace
import SwiftUI

/// Okno planu (UG 17, PD-OPT-001): polecenie u góry, pod nim plan w drzewie z kosztem, liczbą wierszy, bajtami i czasem,
/// cel optymalizatora, nawigacja w kolejności wykonania, predykaty wybranego kroku, zapis jako tekst/HTML/XML.
final class ExplainPlanViewController: NSViewController, DocumentContentController {
    private let document: PelikanWorkspace.Document
    private let workspace: Workspace
    private var editor: CodeEditorView!
    private let split = NSSplitView()

    var preferredFirstResponder: NSView { editor.textView }

    init(document: PelikanWorkspace.Document, workspace: Workspace) {
        self.document = document
        self.workspace = workspace
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        editor = CodeEditorView(document: document, fontSize: CGFloat(workspace.settings.editorFontSize))
        split.isVertical = false
        split.dividerStyle = .thin
        split.addArrangedSubview(editor)
        split.addArrangedSubview(NSHostingView(rootView: PlanPanel(document: document, workspace: workspace).interfaceFont()))
        view = split
    }

    private var positioned = false

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !positioned else { return }
        positioned = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.split.layoutSubtreeIfNeeded()
            self.split.setPosition(max(100, self.split.bounds.height * 0.3), ofDividerAt: 0)
        }
    }
}

struct PlanPanel: View {
    /// Sortowanie planu po kolumnie (D212).
    @State private var sortPlan: [ColumnSort<PlanLine>] = []
    /// Filtr, kopiowanie i eksport kroków planu (D214).
    @State private var tools = TableToolsState()
    /// Cel komend `table.*` (D214) — rejestrowany z widokiem NSTableView tabeli planu przy zdobyciu fokusu.
    @StateObject private var tableHandle = SwiftUITableHandle()
    @Bindable var document: PelikanWorkspace.Document
    let workspace: Workspace
    @State private var selection: PlanLine.ID?
    /// Widok planu: drzewo, diagram, flame graph kosztu, tekst DBMS_XPLAN (SD-PLAN-001).
    @State private var mode = PlanPanel.initialMode
    /// Widok startowy panelu (krok `debug.planMode` skryptu zrzutów).
    static var initialMode = 0

    private var ordered: [PlanLine] { document.plan?.executionOrder ?? [] }

    private var planColumns: [DataColumn<PlanLine>] {
        let num: (Int64?) -> String = { $0.map(String.init) ?? "" }
        return [
            DataColumn(L10n.tr("Opis"), sortKey: { (l: PlanLine) in l.title }) { (l: PlanLine) in
                Text(l.title).fontWeight(l.id == selection ? .semibold : .regular)
            }.width(min: 200, ideal: 280),
            DataColumn(L10n.tr("Obiekt"), text: { (l: PlanLine) in l.object }).width(min: 80, ideal: 160),
            DataColumn(L10n.tr("Koszt"), sortKey: { (l: PlanLine) in l.cost }, text: { num($0.cost) }) { (l: PlanLine) in Text(num(l.cost)).monospacedDigit() }.width(60),
            DataColumn(L10n.tr("Wiersze"), sortKey: { (l: PlanLine) in l.cardinality }, text: { num($0.cardinality) }) { (l: PlanLine) in Text(num(l.cardinality)).monospacedDigit() }.width(70),
            DataColumn(L10n.tr("Bajty"), sortKey: { (l: PlanLine) in l.bytes }, text: { num($0.bytes) }) { (l: PlanLine) in Text(num(l.bytes)).monospacedDigit() }.width(70),
            DataColumn(L10n.tr("Czas"), sortKey: { (l: PlanLine) in l.time }, text: { num($0.time) }) { (l: PlanLine) in Text(num(l.time)).monospacedDigit() }.width(50),
            DataColumn(L10n.tr("Kolejność"), sortKey: { (l: PlanLine) in l.executionOrder }) { (l: PlanLine) in Text("\(l.executionOrder)").monospacedDigit() }.width(60),
        ]
    }

    /// Kroki planu spełniające filtr; nil — filtr pusty (widok drzewa).
    private var filteredLines: [PlanLine]? { Self.filtered(document.plan, columns: planColumnValues, filter: tools.filter) }

    /// Kolumna planu bez widoku komórki (tekst i klucz) — dla uchwytu tabeli, który nie może trzymać widoku
    /// (widok kolumny „Opis” czyta zaznaczenie, czyli trzyma `self` z uchwytem w `@State`).
    typealias PlanColumn = (id: String, title: String, text: (PlanLine) -> String, key: (PlanLine) -> SortKey)

    private var planColumnValues: [PlanColumn] { planColumns.map { ($0.id, $0.title, $0.text, $0.key) } }

    /// Wiersze tabeli planu do kopii, eksportu, licznika i numerów `rows` komend: z filtrem — pasujące kroki
    /// posortowane; bez filtra — cały plan w kolejności drzewa (rodzeństwo posortowane jak na ekranie), także kroki
    /// w gałęziach zwiniętych. Spór rund 12–13 rozstrzygnięty zasadą weta (D224): więcej informacji — eksport nie gubi
    /// kroków.
    static func planRows(_ plan: ExplainPlanResult?, filtered: [PlanLine]?, sort: [ColumnSort<PlanLine>]) -> [PlanLine] {
        if let filtered { return filtered.sorted(by: sort) }
        var out: [PlanLine] = []
        func add(_ l: PlanLine) {
            out.append(l)
            (l.children ?? []).sorted(by: sort).forEach(add)
        }
        (plan?.roots ?? []).sorted(by: sort).forEach(add)
        return out
    }

    /// Kroki spełniające filtr; nil — filtr pusty.
    static func filtered(_ plan: ExplainPlanResult?, columns: [PlanColumn], filter: TableFilter) -> [PlanLine]? {
        guard filter.isActive else { return nil }
        return filterRows(plan?.lines ?? [], columns: columns.map { ($0.id, $0.text, $0.key) }, filter: filter)
    }

    static func contents(_ shown: [PlanLine], columns cols: [PlanColumn], selected: PlanLine.ID?) -> TableContents {
        TableContents.make(title: L10n.tr("Plan wykonania"), columns: cols.map { ($0.id, $0.title, $0.text) }, shown: shown,
                           isSelected: { $0.id == selected })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Dwa wiersze: przy jednym w oknie o typowej szerokości selektor celu i „Odśwież plan” ściskały się do zera.
            HStack(spacing: 8) {
                Button { workspace.perform("tools.explainPlan") } label: { Label(L10n.tr("Odśwież plan"), systemImage: "play.fill") }
                    .disabled(document.isExecuting)
                    .fixedSize()
                Picker(L10n.tr("Cel optymalizatora"), selection: $document.planGoal) {
                    ForEach(OptimizerGoal.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .fixedSize()
                Divider().frame(height: 18)
                Button { move(to: ordered.first) } label: { Image(systemName: "backward.end") }.iconLabel(L10n.tr("Pierwszy krok wykonania"))
                Button { step(-1) } label: { Image(systemName: "backward") }.iconLabel(L10n.tr("Poprzedni krok wykonania"))
                Button { step(1) } label: { Image(systemName: "forward") }.iconLabel(L10n.tr("Następny krok wykonania"))
                Button { move(to: ordered.last) } label: { Image(systemName: "forward.end") }.iconLabel(L10n.tr("Ostatni krok wykonania"))
                Spacer()
            }
            HStack(spacing: 8) {
                Picker("", selection: $mode) {
                    Text(L10n.tr("Drzewo")).tag(0)
                    Text(L10n.tr("Diagram")).tag(1)
                    Text(L10n.tr("Flame graph")).tag(2)
                    Text(L10n.tr("Tekst")).tag(3)
                }
                .pickerStyle(.segmented).fixedSize()
                Button { workspace.perform("plan.expandAll") } label: { Image(systemName: "chevron.down.2") }
                    .iconLabel(L10n.tr("Rozwiń wszystkie gałęzie"))
                    .disabled(document.plan?.branchIDs.isEmpty ?? true || mode != 0)
                Button { workspace.perform("plan.collapseAll") } label: { Image(systemName: "chevron.up.2") }
                    .iconLabel(L10n.tr("Zwiń wszystkie gałęzie"))
                    .disabled(document.plan?.branchIDs.isEmpty ?? true || mode != 0)
                Spacer()
                Button(L10n.tr("Porównaj")) { workspace.perform("plan.compare") }.disabled(document.previousPlan == nil)
                    .help(L10n.tr("Porównaj z poprzednim planem okna"))
                Button(L10n.tr("Autotrace")) { workspace.perform("tools.autotrace") }.disabled(document.isExecuting)
                Menu(L10n.tr("Zapisz")) {
                    ForEach(PlanFormat.allCases, id: \.self) { f in
                        Button(f.rawValue.uppercased()) { workspace.perform("plan.export", CommandArguments(["format": .string(f.rawValue)])) }
                    }
                }
                .fixedSize()
                .disabled(document.plan == nil)
            }
            if let e = document.planError { Text(e).foregroundStyle(.red).font(.ui).textSelection(.enabled) }
            if mode == 1, let plan = document.plan {
                PlanDiagramView(roots: plan.roots, selection: $selection)
            } else if mode == 2, let plan = document.plan {
                FlameGraphView(roots: plan.roots, selection: $selection)
            } else if mode == 3, let plan = document.plan {
                ScrollView([.horizontal, .vertical]) {
                    Text(plan.text).font(.code).textSelection(.enabled).padding(4)
                }
            } else {
                // Rozwinięcie gałęzi w modelu okna (`planExpanded`) — komendy Rozwiń/Zwiń wszystko (PD-OPT-001).
                let lines = filteredLines
                let shownLines = Self.planRows(document.plan, filtered: lines, sort: sortPlan)
                let cols = planColumnValues
                let contents = Self.contents(shownLines, columns: cols, selected: selection)
                let handle = tableHandle
                // Komendy liczą wiersze widoku przy wywołaniu (bieżący filtr, sortowanie, rozwinięcie, zaznaczenie);
                // domknięcia trzymają dokument i teksty kolumn, nie widok.
                let (doc, toolsState, sortState, selectionState) = (document, $tools, $sortPlan, $selection)
                let _ = handle.update(rows: {
                                          Self.planRows(doc.plan, filtered: Self.filtered(doc.plan, columns: cols, filter: toolsState.wrappedValue.filter),
                                                        sort: sortState.wrappedValue)
                                      },
                                      contents: { Self.contents($0, columns: cols, selected: selectionState.wrappedValue) },
                                      state: $tools, sqlTarget: nil)
                TableToolsBar(contents: contents, handle: handle, state: $tools, total: document.plan?.lines.count ?? 0)
                ScrollViewReader { proxy in
                    Table(of: PlanLine.self, selection: $selection, sortOrder: $sortPlan) {
                        TableColumnForEach(planColumns) { c in
                            TableColumn(c.title, sortUsing: ColumnSort(c.id, c.key)) { (l: PlanLine) in
                                if let content = c.content { content(l) } else { Text(c.text(l)) }
                            }
                            .width(min: c.minWidth, ideal: c.idealWidth, max: c.maxWidth)
                        }
                    } rows: {
                        // Filtr (D214): pasujące kroki jako płaska lista; bez filtra — drzewo planu.
                        if lines != nil {
                            ForEach(shownLines) { TableRow($0) }
                        } else {
                            ForEach((document.plan?.roots ?? []).sorted(by: sortPlan)) { PlanTreeRows(line: $0, expanded: $document.planExpanded, sort: sortPlan) }
                        }
                    }
                    .registersTable(handle)
                    .contextMenu(forSelectionType: PlanLine.ID.self) { ids in
                        // Migawka z chwili otwarcia menu (jak w DataTable).
                        let frozen = FrozenTable(handle, contents: contents, indexes: SwiftUITableHandle.indexer(shownLines))
                        TableCopyMenu(contents: contents, handle: frozen, marked: tools.markedColumns, rows: .from(ids, shown: shownLines))
                        if let id = ids.first {
                            Divider()
                            TableValueFilterMenu(columns: contents.columns, handle: frozen, rowID: AnyHashable(id))
                        }
                        Divider()
                        Menu(L10n.tr("Eksportuj")) { TableExportMenu(handle: handle) }
                    }
                    // Krok zaznaczony nawigacją albo w Diagramie/Flame graph: rozwinięte gałęzie nad nim i przewinięcie do niego.
                    .onChange(of: selection, initial: true) { _, id in
                        guard let id else { return }
                        document.revealPlanLine(id)
                        DispatchQueue.main.async { proxy.scrollTo(id) }
                    }
                }
                if let line = document.plan?.lines.first(where: { $0.id == selection }), !(line.accessPredicates.isEmpty && line.filterPredicates.isEmpty) {
                    VStack(alignment: .leading, spacing: 2) {
                        if !line.accessPredicates.isEmpty { Text(L10n.tr("Dostęp: \(line.accessPredicates)")).font(.code).textSelection(.enabled) }
                        if !line.filterPredicates.isEmpty { Text(L10n.tr("Filtr: \(line.filterPredicates)")).font(.code).textSelection(.enabled) }
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func move(to line: PlanLine?) { selection = line?.id }

    private func step(_ delta: Int) {
        guard !ordered.isEmpty else { return }
        let i = ordered.firstIndex { $0.id == selection } ?? (delta > 0 ? -1 : ordered.count)
        selection = ordered[max(0, min(ordered.count - 1, i + delta))].id
    }
}

/// Wiersze drzewa planu: gałąź jako wiersz z rozwijaniem sterowanym zbiorem rozwiniętych kroków okna.
struct PlanTreeRows: TableRowContent {
    let line: PlanLine
    @Binding var expanded: Set<Int>
    /// Sortowanie po kolumnie (D212): gałęzie planu zostają, kolejność zmienia się wśród rodzeństwa.
    var sort: [ColumnSort<PlanLine>] = []

    @TableRowBuilder<PlanLine> var tableRowBody: some TableRowContent<PlanLine> {
        if let children = line.children {
            DisclosureTableRow(line, isExpanded: Binding(get: { expanded.contains(line.id) }, set: { open in
                if open { expanded.insert(line.id) } else { expanded.remove(line.id) }
            })) {
                ForEach(children.sorted(by: sort)) { PlanTreeRows(line: $0, expanded: $expanded, sort: sort) }
            }
        } else {
            TableRow(line)
        }
    }
}
