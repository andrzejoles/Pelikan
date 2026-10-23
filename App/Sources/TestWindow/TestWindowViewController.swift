import AppKit
import PelikanWorkspace
import SwiftUI

/// Okno testu (UG 5): blok PL/SQL u góry, pod nim karty Zmienne / Wyjście / Stos błędu; F8 wykonuje blok.
final class TestWindowViewController: NSViewController {
    private let document: PelikanWorkspace.Document
    private let workspace: Workspace
    private var editor: CodeEditorView!
    private let split = NSSplitView()
    private var tokens: [ObservationToken] = []
    private var scanWork: DispatchWorkItem?

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
        let bottom = NSHostingView(rootView: TestPanel(document: document, workspace: workspace))
        split.isVertical = false
        split.dividerStyle = .thin
        split.addArrangedSubview(editor)
        split.addArrangedSubview(bottom)
        view = split
        TestRunner.synchronize(document)
        // Skanowanie zmiennych po zmianie tekstu (UG 23.21 „automatyczne skanowanie”).
        tokens.append(trackChanges { [weak self] in
            guard let self else { return }
            _ = self.document.text
            self.scanWork?.cancel()
            let w = DispatchWorkItem { [weak self] in if let d = self?.document { TestRunner.synchronize(d) } }
            self.scanWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: w)
        })
    }

    private var positioned = false

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !positioned else { return }
        positioned = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.split.layoutSubtreeIfNeeded()
            self.split.setPosition(max(160, self.split.bounds.height * 0.55), ofDividerAt: 0)
        }
    }
}

/// Karty pod blokiem testu.
struct TestPanel: View {
    @Bindable var document: PelikanWorkspace.Document
    let workspace: Workspace
    @State private var tab = 0
    @State private var cursorShown: TestVariable?

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text(L10n.tr("Zmienne")).tag(0)
                Text(L10n.tr("Wyjście")).tag(1)
                Text(L10n.tr("Stos błędu") + (document.errorStack.isEmpty ? "" : " (\(document.errorStack.count))")).tag(2)
                Text(L10n.tr("Profiler")).tag(3)
                Text(L10n.tr("Statystyki")).tag(4)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(6)
            switch tab {
            case 0: variables
            case 1: output
            case 2: errorStack
            case 3: profiler
            default: statistics
            }
        }
        .onChange(of: document.errorStack) { if !document.errorStack.isEmpty { tab = 2 } }
        .sheet(item: $cursorShown) { v in CursorResultView(variable: v) }
    }

    private var variables: some View {
        Table($document.testVariables) {
            TableColumn(L10n.tr("Zmienna")) { $v in Text(v.name).font(.system(.body, design: .monospaced)) }.width(min: 90, ideal: 140)
            TableColumn(L10n.tr("Typ")) { $v in
                Picker("", selection: $v.type) {
                    ForEach(TestVariableType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }.labelsHidden()
            }.width(min: 110, ideal: 140)
            TableColumn(L10n.tr("Wartość")) { $v in
                HStack {
                    if v.type == .cursor {
                        Text(v.value).foregroundStyle(.secondary)
                        Spacer()
                        Button("…") { cursorShown = v }.disabled(v.cursorColumns.isEmpty)
                    } else {
                        TextField(v.isNull ? L10n.tr("(null)") : "", text: Binding(get: { v.value }, set: { v.value = $0; v.isNull = $0.isEmpty; v.changed = false }))
                            .font(.system(.body, design: .monospaced))
                    }
                }
                .padding(.horizontal, 4)
                .background(v.changed ? Color.yellow.opacity(0.35) : Color.clear)
            }
        }
    }

    private var output: some View {
        ScrollView {
            Text(document.output.joined(separator: "\n"))
                .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading).padding(8)
        }
    }

    private var errorStack: some View {
        List(Array(document.errorStack.enumerated()), id: \.offset) { _, f in
            Button {
                open(f)
            } label: {
                HStack {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.red)
                    Text(f.unit.isEmpty ? L10n.tr("Blok testu") : "\(f.owner).\(f.unit)").font(.system(.body, design: .monospaced))
                    Text(L10n.tr("linia \(f.line)")).foregroundStyle(.red)
                }
            }
            .buttonStyle(.plain)
        }
    }

    @State private var statFilter = ""

    private var profiler: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(L10n.tr("Profiler przy wykonaniu"), selection: $document.profiler) {
                Text(L10n.tr("Wyłączony")).tag(ProfilerKind?.none)
                Text(L10n.tr("Liniowy (DBMS_PROFILER)")).tag(ProfilerKind?.some(.lines))
                Text(L10n.tr("Hierarchiczny (DBMS_HPROF)")).tag(ProfilerKind?.some(.hierarchical))
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 6)
            if let r = document.profilerReport {
                if r.kind == .lines {
                    let total = max(r.lines.reduce(0) { $0 + $1.totalTime }, 1)
                    Table(r.lines) {
                        TableColumn(L10n.tr("Jednostka")) { (l: ProfilerLine) in Text(l.unitName.isEmpty ? L10n.tr("blok") : l.unitName) }.width(min: 90, ideal: 140)
                        TableColumn(L10n.tr("Linia")) { (l: ProfilerLine) in Text(String(l.line)) }.width(44)
                        TableColumn(L10n.tr("Wykonań")) { (l: ProfilerLine) in Text(String(l.occurrences)) }.width(64)
                        TableColumn(L10n.tr("Czas [ms]")) { (l: ProfilerLine) in Text(String(format: "%.3f", l.totalTime / 1e6)) }.width(74)
                        TableColumn("%") { (l: ProfilerLine) in bar(l.totalTime / total) }.width(90)
                        TableColumn(L10n.tr("Tekst")) { (l: ProfilerLine) in Text(l.text).font(.system(size: 11, design: .monospaced)).lineLimit(1) }
                    }
                } else {
                    let total = max(r.functions.map(\.subtreeTime).max() ?? 1, 1)
                    Table(r.functions) {
                        TableColumn(L10n.tr("Funkcja")) { (f: ProfilerFunction) in Text(f.displayName).font(.system(.body, design: .monospaced)) }.width(min: 160, ideal: 240)
                        TableColumn(L10n.tr("Wywołań")) { (f: ProfilerFunction) in Text(String(f.calls)) }.width(64)
                        TableColumn(L10n.tr("Własny [µs]")) { (f: ProfilerFunction) in Text(String(format: "%.0f", f.functionTime)) }.width(84)
                        TableColumn(L10n.tr("Z wywołaniami [µs]")) { (f: ProfilerFunction) in Text(String(format: "%.0f", f.subtreeTime)) }.width(120)
                        TableColumn("%") { (f: ProfilerFunction) in bar(f.subtreeTime / total) }.width(90)
                    }
                }
            } else {
                Text(L10n.tr("Włącz profiler i wykonaj blok (F8) — raport pojawi się tutaj.")).foregroundStyle(.secondary).padding(8)
                Spacer()
            }
        }
    }

    private func bar(_ fraction: Double) -> some View {
        GeometryReader { g in
            Rectangle().fill(Color.orange.opacity(0.7)).frame(width: max(1, g.size.width * min(1, fraction)))
        }
        .frame(height: 10)
        .help(String(format: "%.1f%%", fraction * 100))
    }

    private var statistics: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(L10n.tr("Filtr statystyk"), text: $statFilter).textFieldStyle(.roundedBorder).padding(.horizontal, 6)
            Table(document.statistics.filter { statFilter.isEmpty || $0.name.localizedCaseInsensitiveContains(statFilter) }) {
                TableColumn(L10n.tr("Statystyka")) { (s: SessionStatistic) in Text(s.name) }
                TableColumn(L10n.tr("Wartość")) { (s: SessionStatistic) in Text(String(format: s.value.rounded() == s.value ? "%.0f" : "%.2f", s.value)) }.width(120)
            }
        }
    }

    /// Ramka stosu: blok testu — kursor w linii; jednostka — źródło w oknie programu na linii (UG 5.5).
    private func open(_ f: ErrorStackFrame) {
        if f.unit.isEmpty {
            let o = ProgramCompiler.offset(line: f.line, column: 1, in: document.text)
            document.selectedRange = o..<o
            return
        }
        Task {
            guard let m = workspace.metadata(for: workspace.effectiveConnection(of: document)),
                  let o = try? await m.find("\"\(f.owner)\".\"\(f.unit)\"") else { return }
            // Linie stosu odnoszą się do ciała pakietu/typu, jeśli istnieje.
            let body = DBObject(owner: o.owner, name: o.name, type: o.type == .package ? .packageBody : o.type == .type ? .typeBody : o.type)
            try? await workspace.openObject(body, line: f.line)
        }
    }
}

/// Wynik kursora zmiennej (pierwsze wiersze).
struct CursorResultView: View {
    let variable: TestVariable
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading) {
            Text(":\(variable.name)").font(.headline)
            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow { ForEach(variable.cursorColumns, id: \.self) { Text($0).bold() } }
                    ForEach(Array(variable.cursorRows.enumerated()), id: \.offset) { _, row in
                        GridRow { ForEach(Array(row.enumerated()), id: \.offset) { _, c in Text(c).font(.system(size: 11, design: .monospaced)) } }
                    }
                }
                .padding(6)
            }
            HStack { Spacer(); Button(L10n.tr("Zamknij")) { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(14)
        .frame(minWidth: 480, minHeight: 300)
    }
}
