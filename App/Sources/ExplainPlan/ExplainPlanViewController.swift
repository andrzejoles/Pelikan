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
    @State private var showText = false

    private var ordered: [PlanLine] { document.plan?.executionOrder ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button { workspace.perform("tools.explainPlan") } label: { Label(L10n.tr("Wyjaśnij"), systemImage: "play.fill") }
                    .disabled(document.isExecuting)
                Picker(L10n.tr("Cel optymalizatora"), selection: $document.planGoal) {
                    ForEach(OptimizerGoal.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .frame(maxWidth: 260)
                Divider().frame(height: 18)
                Button { move(to: ordered.first) } label: { Image(systemName: "backward.end") }.help(L10n.tr("Pierwszy krok wykonania"))
                Button { step(-1) } label: { Image(systemName: "backward") }.help(L10n.tr("Poprzedni krok wykonania"))
                Button { step(1) } label: { Image(systemName: "forward") }.help(L10n.tr("Następny krok wykonania"))
                Button { move(to: ordered.last) } label: { Image(systemName: "forward.end") }.help(L10n.tr("Ostatni krok wykonania"))
                Spacer()
                Toggle(L10n.tr("Tekst DBMS_XPLAN"), isOn: $showText).toggleStyle(.checkbox)
                Menu(L10n.tr("Zapisz")) {
                    ForEach(PlanFormat.allCases, id: \.self) { f in
                        Button(f.rawValue.uppercased()) { workspace.perform("plan.export", CommandArguments(["format": .string(f.rawValue)])) }
                    }
                }
                .fixedSize()
                .disabled(document.plan == nil)
            }
            if let e = document.planError { Text(e).foregroundStyle(.red).font(.callout).textSelection(.enabled) }
            if showText, let plan = document.plan {
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
    }

    private func move(to line: PlanLine?) { selection = line?.id }

    private func step(_ delta: Int) {
        guard !ordered.isEmpty else { return }
        let i = ordered.firstIndex { $0.id == selection } ?? (delta > 0 ? -1 : ordered.count)
        selection = ordered[max(0, min(ordered.count - 1, i + delta))].id
    }
}
