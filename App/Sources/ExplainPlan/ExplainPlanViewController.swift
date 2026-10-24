import AppKit
import PelikanWorkspace
import SwiftUI

/// Okno planu (UG 17, PD-OPT-001): polecenie u góry, pod nim plan w drzewie z kosztem, liczbą wierszy, bajtami i czasem,
/// cel optymalizatora, nawigacja w kolejności wykonania, predykaty wybranego kroku, zapis jako tekst/HTML/XML.
final class ExplainPlanViewController: NSViewController {
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
        split.addArrangedSubview(NSHostingView(rootView: PlanPanel(document: document, workspace: workspace)))
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
    @Bindable var document: PelikanWorkspace.Document
    let workspace: Workspace
    @State private var selection: PlanLine.ID?
    /// Widok planu: drzewo, diagram, flame graph kosztu, tekst DBMS_XPLAN (SD-PLAN-001).
    @State private var mode = PlanPanel.initialMode
    /// Widok startowy panelu (krok `debug.planMode` skryptu zrzutów).
    static var initialMode = 0

    private var ordered: [PlanLine] { document.plan?.executionOrder ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Dwa wiersze: przy jednym w oknie o typowej szerokości selektor celu i „Wyjaśnij” ściskały się do zera.
            HStack(spacing: 8) {
                Button { workspace.perform("tools.explainPlan") } label: { Label(L10n.tr("Wyjaśnij"), systemImage: "play.fill") }
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
            if let e = document.planError { Text(e).foregroundStyle(.red).font(.callout).textSelection(.enabled) }
            if mode == 1, let plan = document.plan {
                PlanDiagramView(roots: plan.roots, selection: $selection)
            } else if mode == 2, let plan = document.plan {
                FlameGraphView(roots: plan.roots, selection: $selection)
            } else if mode == 3, let plan = document.plan {
                ScrollView([.horizontal, .vertical]) {
                    Text(plan.text).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).padding(4)
                }
            } else {
                Table(document.plan?.roots ?? [], children: \.children, selection: $selection) {
                    TableColumn(L10n.tr("Opis")) { l in
                        Text(l.title).fontWeight(l.id == selection ? .semibold : .regular)
                    }
                    .width(min: 200, ideal: 280)
                    TableColumn(L10n.tr("Obiekt")) { l in Text(l.object) }.width(min: 80, ideal: 160)
                    TableColumn(L10n.tr("Koszt")) { l in Text(l.cost.map(String.init) ?? "").monospacedDigit() }.width(60)
                    TableColumn(L10n.tr("Wiersze")) { l in Text(l.cardinality.map(String.init) ?? "").monospacedDigit() }.width(70)
                    TableColumn(L10n.tr("Bajty")) { l in Text(l.bytes.map(String.init) ?? "").monospacedDigit() }.width(70)
                    TableColumn(L10n.tr("Czas")) { l in Text(l.time.map(String.init) ?? "").monospacedDigit() }.width(50)
                    TableColumn(L10n.tr("Kolejność")) { l in Text("\(l.executionOrder)").monospacedDigit() }.width(60)
                }
                if let line = document.plan?.lines.first(where: { $0.id == selection }), !(line.accessPredicates.isEmpty && line.filterPredicates.isEmpty) {
                    VStack(alignment: .leading, spacing: 2) {
                        if !line.accessPredicates.isEmpty { Text(L10n.tr("Dostęp: \(line.accessPredicates)")).font(.caption.monospaced()).textSelection(.enabled) }
                        if !line.filterPredicates.isEmpty { Text(L10n.tr("Filtr: \(line.filterPredicates)")).font(.caption.monospaced()).textSelection(.enabled) }
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
