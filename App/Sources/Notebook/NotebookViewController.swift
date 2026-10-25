import AppKit
import Charts
import PelikanDB
import PelikanWorkspace
import SwiftUI

/// Okno notatnika SQL (SD-NB-001/002): komórki Markdown i SQL, wykonanie komórki i Run All, wyniki i wykresy
/// zapisywane w pliku notatnika.
final class NotebookViewController: NSViewController {
    private let document: PelikanWorkspace.Document
    private let workspace: Workspace

    init(document: PelikanWorkspace.Document, workspace: Workspace) {
        self.document = document
        self.workspace = workspace
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSHostingView(rootView: NotebookView(document: document, workspace: workspace))
    }
}

struct NotebookView: View {
    let document: PelikanWorkspace.Document
    let workspace: Workspace
    @State private var running: Int?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(L10n.tr("Wykonaj wszystkie")) { Task { await runAll() } }.disabled(running != nil)
                Menu(L10n.tr("Dodaj komórkę")) {
                    Button("SQL") { add(.sql) }
                    Button("Markdown") { add(.markdown) }
                }
                .fixedSize()
                Spacer()
                if running != nil { ProgressView().controlSize(.small) }
                Button(L10n.tr("Eksport Markdown…")) {
                    Task {
                        do { try await workspace.invoke("notebook.exportMarkdown") } catch CommandError.cancelledByUser {
                        } catch { workspace.ui?.showError(error.localizedDescription) }
                    }
                }
            }
            .padding(8)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(document.notebook.cells.enumerated()), id: \.element.id) { i, _ in
                        NotebookCellView(document: document, index: i, running: running == i,
                                         run: { Task { await run(i) } }, remove: { remove(i) }, move: { move(i, by: $0) })
                    }
                }
                .padding(12)
            }
        }
    }

    private func add(_ kind: NotebookCell.Kind) {
        document.notebook.cells.append(NotebookCell(kind: kind, text: ""))
        document.isModified = true
    }

    private func remove(_ i: Int) {
        guard document.notebook.cells.indices.contains(i) else { return }
        document.notebook.cells.remove(at: i)
        document.isModified = true
    }

    private func move(_ i: Int, by d: Int) {
        let j = i + d
        guard document.notebook.cells.indices.contains(i), document.notebook.cells.indices.contains(j) else { return }
        document.notebook.cells.swapAt(i, j)
        document.isModified = true
    }

    private func run(_ i: Int) async {
        running = i
        await NotebookRunner.run(cell: i, in: document, ws: workspace)
        running = nil
    }

    private func runAll() async {
        for i in document.notebook.cells.indices where document.notebook.cells[i].kind == .sql {
            await run(i)
            if document.notebook.cells[i].result?.error != nil { break }
        }
    }
}

struct NotebookCellView: View {
    let document: PelikanWorkspace.Document
    let index: Int
    let running: Bool
    let run: () -> Void
    let remove: () -> Void
    let move: (Int) -> Void
    @State private var editing = false

    private var cell: Binding<NotebookCell> {
        Binding(get: { document.notebook.cells.indices.contains(index) ? document.notebook.cells[index] : NotebookCell(kind: .sql, text: "") },
                set: { if document.notebook.cells.indices.contains(index) { document.notebook.cells[index] = $0; document.isModified = true } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(cell.wrappedValue.kind == .sql ? "SQL" : "Markdown").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                if cell.wrappedValue.kind == .sql {
                    Button { run() } label: { Image(systemName: "play.fill") }.iconLabel(L10n.tr("Wykonaj komórkę")).disabled(running)
                    Button { toggleChart() } label: { Image(systemName: "chart.bar") }.iconLabel(L10n.tr("Wykres z wyniku"))
                        .disabled(cell.wrappedValue.result?.columns.isEmpty ?? true)
                } else {
                    Button(editing ? L10n.tr("Gotowe") : L10n.tr("Edytuj")) { editing.toggle() }
                }
                Button { move(-1) } label: { Image(systemName: "arrow.up") }.iconLabel(L10n.tr("Przesuń w górę"))
                Button { move(1) } label: { Image(systemName: "arrow.down") }.iconLabel(L10n.tr("Przesuń w dół"))
                Button { remove() } label: { Image(systemName: "trash") }.iconLabel(L10n.tr("Usuń"))
            }
            .buttonStyle(.borderless)
            if cell.wrappedValue.kind == .markdown && !editing && !cell.wrappedValue.text.isEmpty {
                Text((try? AttributedString(markdown: cell.wrappedValue.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(cell.wrappedValue.text))
                    .textSelection(.enabled)
                    .onTapGesture(count: 2) { editing = true }
            } else {
                TextEditor(text: cell.text)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 60, maxHeight: 220)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator))
            }
            if let r = cell.wrappedValue.result { result(r) }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
    }

    @ViewBuilder private func result(_ r: NotebookResult) -> some View {
        if let e = r.error {
            Text(e).foregroundStyle(.red).textSelection(.enabled)
        }
        if !r.columns.isEmpty {
            if let c = cell.wrappedValue.chart {
                SimpleChartView(data: r.chartData(c), kind: c.kind).frame(height: 220)
            }
            SimpleGridView(columns: r.columns, rows: r.rows.map { $0.map { $0 ?? "" } }).frame(maxHeight: 260)
            if r.truncated { Text(L10n.tr("Wynik obcięty do \(r.rows.count) wierszy")).font(.caption).foregroundStyle(.orange) }
        }
        ForEach(Array((r.messages + r.output).enumerated()), id: \.offset) { _, line in
            Text(line).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
        }
        Text(L10n.tr("Czas: \(String(format: "%.3f", Double(r.milliseconds) / 1000)) s")).font(.caption2).foregroundStyle(.secondary)
    }

    private func toggleChart() {
        guard let r = cell.wrappedValue.result else { return }
        cell.wrappedValue.chart = cell.wrappedValue.chart == nil ? r.suggestedChart() : nil
    }
}

/// Prosta siatka tekstowa (wyniki notatnika i raportów).
struct SimpleGridView: View {
    let columns: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
                GridRow { ForEach(Array(columns.enumerated()), id: \.offset) { _, c in Text(c).font(.caption.bold()) } }
                Divider()
                ForEach(Array(rows.prefix(1000).enumerated()), id: \.offset) { _, r in
                    GridRow { ForEach(Array(r.enumerated()), id: \.offset) { _, v in Text(v).font(.system(.caption, design: .monospaced)).lineLimit(1) } }
                }
            }
            .textSelection(.enabled)
            .padding(6)
        }
    }
}

/// Prosty wykres z gotowych danych (słupkowy, liniowy, kołowy, punktowy, warstwowy).
struct SimpleChartView: View {
    let data: ChartData
    let kind: ChartKind

    var body: some View {
        Chart(data.points) { p in
            switch kind {
            case .line: LineMark(x: .value(L10n.tr("Kategoria"), p.category), y: .value(L10n.tr("Wartość"), p.value)).foregroundStyle(by: .value(L10n.tr("Seria"), p.series))
            case .area: AreaMark(x: .value(L10n.tr("Kategoria"), p.category), y: .value(L10n.tr("Wartość"), p.value)).foregroundStyle(by: .value(L10n.tr("Seria"), p.series))
            case .point: PointMark(x: .value(L10n.tr("Kategoria"), p.category), y: .value(L10n.tr("Wartość"), p.value)).foregroundStyle(by: .value(L10n.tr("Seria"), p.series))
            case .pie: SectorMark(angle: .value(L10n.tr("Wartość"), max(0, p.value)), innerRadius: .ratio(0.4)).foregroundStyle(by: .value(L10n.tr("Kategoria"), p.category))
            case .bar: BarMark(x: .value(L10n.tr("Kategoria"), p.category), y: .value(L10n.tr("Wartość"), p.value))
                .foregroundStyle(by: .value(L10n.tr("Seria"), p.series)).position(by: .value(L10n.tr("Seria"), p.series))
            }
        }
    }
}
