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
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(6)
            switch tab {
            case 0: variables
            case 1: output
            default: errorStack
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
