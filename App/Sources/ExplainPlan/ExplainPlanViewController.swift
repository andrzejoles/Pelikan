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
    /// Cel komend `table.*` (D214) — zapis przy fokusie i zaznaczeniu wiersza przez użytkownika.
    @State private var tableHandle = SwiftUITableHandle()
    @FocusState private var tableFocused: Bool
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
    private var filteredLines: [PlanLine]? {
        let f = tools.filter.compiled()
        guard !f.isEmpty else { return nil }
        let cols = planColumns
        let ids = cols.map(\.id)
        return (document.plan?.lines ?? []).filter { l in
            f.matches(all: ids) { id in cols.first { $0.id == id }.map { ($0.text(l), $0.key(l)) } ?? ("", .none) }
        }
    }

    private func planContents(_ lines: [PlanLine]) -> TableContents {
        let cols = planColumns
        let shown = lines.sorted(by: sortPlan)
        return TableContents(title: L10n.tr("Plan wykonania"), columns: cols.map { ($0.id, $0.title) }, rowCount: shown.count,
                             cell: { r, id in r < shown.count ? cols.first { $0.id == id }?.text(shown[r]) ?? "" : "" },
                             selectedRows: shown.indices.filter { shown[$0].id == selection })
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
                // Wiersze w kolejności widoku (po filtrze i sortowaniu) — te same indeksy w menu i w kopii.
                let shownLines = (lines ?? document.plan?.lines ?? []).sorted(by: sortPlan)
                let contents = planContents(lines ?? document.plan?.lines ?? [])
                let handle = tableHandle
                let _ = handle.update(contents: { contents }, sqlTarget: { nil }, state: $tools)
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
                        if let lines {
                            ForEach(lines.sorted(by: sortPlan)) { TableRow($0) }
                        } else {
                            ForEach((document.plan?.roots ?? []).sorted(by: sortPlan)) { PlanTreeRows(line: $0, expanded: $document.planExpanded, sort: sortPlan) }
                        }
                    }
                    .focused($tableFocused)
                    .onChange(of: tableFocused) { _, now in if now { TableFocus.shared.note(handle) } }
                    .onChange(of: selection) { if tableFocused { TableFocus.shared.note(handle) } }
                    .contextMenu(forSelectionType: PlanLine.ID.self) { ids in
                        let rows = shownLines.indices.filter { ids.contains(shownLines[$0].id) }
                        TableCopyMenu(contents: contents, handle: handle, marked: tools.markedColumns, rows: rows)
                        if let r = rows.first {
                            Divider()
                            TableValueFilterMenu(columns: contents.columns, handle: handle, row: r)
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
