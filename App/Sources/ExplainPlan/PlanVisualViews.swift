import AppKit
import Charts
import PelikanWorkspace
import SwiftUI

/// Diagram planu (SD-PLAN-001): węzeł na wiersz, wcięcie wg głębokości, linie do rodzica; w węźle operacja, obiekt,
/// koszt, kardynalność i kolejność wykonania. Szerokość linii łączącej rośnie z kardynalnością.
struct PlanDiagramView: View {
    let roots: [PlanLine]
    @Binding var selection: PlanLine.ID?

    private let colWidth: CGFloat = 46, rowHeight: CGFloat = 58, boxWidth: CGFloat = 300, boxHeight: CGFloat = 46

    var body: some View {
        let nodes = PlanGraph.layout(roots)
        let maxCol = nodes.map(\.column).max() ?? 0
        let maxCard = Double(nodes.compactMap(\.line.cardinality).max() ?? 1)
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    for n in nodes {
                        guard let p = nodes.first(where: { $0.id == n.parentID }) else { continue }
                        var path = Path()
                        let from = CGPoint(x: CGFloat(n.column) * colWidth + 8, y: CGFloat(n.row) * rowHeight + boxHeight / 2 + 8)
                        let to = CGPoint(x: CGFloat(p.column) * colWidth + 20, y: CGFloat(p.row) * rowHeight + boxHeight + 8)
                        path.move(to: from)
                        path.addLine(to: CGPoint(x: to.x, y: from.y))
                        path.addLine(to: to)
                        let card = Double(n.line.cardinality ?? 1)
                        let w = 1 + 5 * log10(max(1, card)) / log10(max(10, maxCard))
                        ctx.stroke(path, with: .color(.secondary), lineWidth: w)
                    }
                }
                .frame(width: CGFloat(maxCol) * colWidth + boxWidth + 40, height: CGFloat(nodes.count) * rowHeight + 20)
                ForEach(nodes) { n in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack {
                            Text("\(n.line.executionOrder)").font(.caption2.monospacedDigit()).foregroundStyle(.white)
                                .padding(.horizontal, 4).background(Capsule().fill(Color.accentColor))
                            Text(n.line.title).font(.callout.bold()).lineLimit(1)
                        }
                        Text(n.line.object).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Text(L10n.tr("koszt \(n.line.cost.map(String.init) ?? "—") · wiersze \(n.line.cardinality.map(String.init) ?? "—")"))
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .padding(4)
                    .frame(width: boxWidth, height: boxHeight, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(selection == n.id ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: selection == n.id ? 2 : 1))
                    .offset(x: CGFloat(n.column) * colWidth + 20, y: CGFloat(n.row) * rowHeight + 8)
                    .onTapGesture { selection = n.id }
                }
            }
            .padding(8)
        }
    }
}

/// Flame graph kosztu (SD-PLAN-001): poziom = głębokość, szerokość = udział w koszcie rodzica.
struct FlameGraphView: View {
    let roots: [PlanLine]
    @Binding var selection: PlanLine.ID?

    var body: some View {
        let bars = PlanGraph.flame(roots)
        let depth = (bars.map(\.depth).max() ?? 0) + 1
        Chart(bars) { b in
            RectangleMark(xStart: .value("od", b.start), xEnd: .value("do", b.start + b.width),
                          yStart: .value("poziom", Double(b.depth)), yEnd: .value("poziom2", Double(b.depth) + 0.9))
                .foregroundStyle(by: .value(L10n.tr("Operacja"), b.title.components(separatedBy: " ").first ?? ""))
                .opacity(selection == nil || selection == b.id ? 1 : 0.45)
                .annotation(position: .overlay) {
                    if b.width > 0.08 { Text(b.title).font(.caption2).lineLimit(1).foregroundStyle(.white) }
                }
        }
        .chartXScale(domain: 0...1)
        .chartYScale(domain: .automatic(includesZero: true, reversed: true))
        .chartYAxis(.hidden)
        .chartXAxis(.hidden)
        .chartOverlay { proxy in
            GeometryReader { g in
                Rectangle().fill(.clear).contentShape(Rectangle()).onTapGesture { p in
                    guard let x: Double = proxy.value(atX: p.x), let y: Double = proxy.value(atY: p.y) else { return }
                    selection = bars.first { $0.depth == Int(y) && x >= $0.start && x <= $0.start + $0.width }?.id
                }
                .frame(width: g.size.width, height: g.size.height)
            }
        }
        .frame(minHeight: CGFloat(depth) * 26)
        .padding(6)
        if let b = bars.first(where: { $0.id == selection }) {
            Text(L10n.tr("\(b.title) — koszt \(b.cost.map(String.init) ?? "—"), udział \(String(format: "%.1f", b.width * 100)) %")).font(.caption)
        }
    }
}

/// Wynik Autotrace (SD-PLAN-002): plan rzeczywisty i statystyki sesji.
struct AutotraceView: View {
    let result: AutotraceResult
    let sql: String
    @State private var tab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(sql).font(.system(size: 11, design: .monospaced)).lineLimit(3).textSelection(.enabled)
            Text(L10n.tr("SQL_ID \(result.sqlID) · wierszy \(result.rowsFetched) · \(String(format: "%.3f", result.elapsedSeconds)) s")).font(.caption).foregroundStyle(.secondary)
            Picker("", selection: $tab) {
                Text(L10n.tr("Plan rzeczywisty")).tag(0)
                Text(L10n.tr("Statystyki")).tag(1)
                Text("DBMS_XPLAN").tag(2)
            }
            .pickerStyle(.segmented).labelsHidden()
            switch tab {
            case 0:
                Table(result.lines) {
                    TableColumn(L10n.tr("Operacja")) { l in Text(String(repeating: "  ", count: l.depth) + l.title).font(.system(size: 11, design: .monospaced)) }
                        .width(min: 220, ideal: 300)
                    TableColumn(L10n.tr("Obiekt")) { l in Text(l.object) }
                    TableColumn("Starts") { l in Text(l.starts.map(String.init) ?? "").monospacedDigit() }.width(55)
                    TableColumn("E-Rows") { l in Text(l.estimatedRows.map(String.init) ?? "").monospacedDigit() }.width(65)
                    TableColumn("A-Rows") { l in
                        Text(l.actualRows.map(String.init) ?? "").monospacedDigit().foregroundStyle(l.misestimated ? .orange : .primary)
                            .help(l.misestimated ? L10n.tr("Szacunek optymalizatora różni się ponad 10 razy — sprawdź statystyki") : "")
                    }.width(65)
                    TableColumn("ms") { l in Text(l.elapsedMs.map { String(format: "%.2f", $0) } ?? "").monospacedDigit() }.width(60)
                    TableColumn(L10n.tr("Bufory")) { l in Text(l.buffers.map(String.init) ?? "").monospacedDigit() }.width(60)
                    TableColumn(L10n.tr("Odczyty")) { l in Text(l.diskReads.map(String.init) ?? "").monospacedDigit() }.width(60)
                }
            case 1:
                Table(result.statistics) {
                    TableColumn(L10n.tr("Statystyka")) { s in Text(s.name) }
                    TableColumn(L10n.tr("Wartość")) { s in Text(String(format: "%.0f", s.value)).monospacedDigit() }.width(120)
                }
            default:
                ScrollView([.horizontal, .vertical]) {
                    Text(result.planText).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).padding(4)
                }
            }
        }
        .padding(10)
        .frame(minWidth: 820, minHeight: 440)
    }
}

/// Porównanie dwóch planów (SD-PLAN-003).
struct PlanComparisonView: View {
    let comparison: PlanComparison
    let leftTitle: String
    let rightTitle: String
    @State private var onlyDifferent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.tr("\(leftTitle): koszt \(comparison.leftCost.map(String.init) ?? "—")  →  \(rightTitle): koszt \(comparison.rightCost.map(String.init) ?? "—")"))
                Spacer()
                Toggle(L10n.tr("Tylko różnice"), isOn: $onlyDifferent).toggleStyle(.checkbox)
            }
            Table(comparison.rows.filter { !onlyDifferent || $0.status != .same }) {
                TableColumn("") { r in Image(systemName: icon(r.status)).foregroundStyle(color(r.status)) }.width(24)
                TableColumn(leftTitle) { r in Text(r.left.map { "\(String(repeating: "  ", count: $0.depth))\($0.title) \($0.object)" } ?? "").font(.system(size: 11, design: .monospaced)) }
                TableColumn(rightTitle) { r in Text(r.right.map { "\(String(repeating: "  ", count: $0.depth))\($0.title) \($0.object)" } ?? "").font(.system(size: 11, design: .monospaced)) }
                TableColumn(L10n.tr("Różnice")) { r in Text(r.differences.joined(separator: ", ")).font(.caption) }
            }
        }
        .padding(10)
        .frame(minWidth: 900, minHeight: 420)
    }

    private func icon(_ s: PlanComparisonRow.Status) -> String {
        switch s { case .same: "equal.circle"; case .changed: "pencil.circle"; case .onlyLeft: "minus.circle"; case .onlyRight: "plus.circle" }
    }

    private func color(_ s: PlanComparisonRow.Status) -> Color {
        switch s { case .same: .secondary; case .changed: .orange; case .onlyLeft: .red; case .onlyRight: .green }
    }
}
