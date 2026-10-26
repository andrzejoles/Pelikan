import AppKit
import PelikanSQL
import PelikanWorkspace
import SwiftUI

/// Przeglądarka różnic (UG 26): dwie kolumny z numerami linii, różnice w obrębie linii, mapa zmian, następna /
/// poprzednia różnica, ignorowanie wielkości liter / białych znaków / komentarzy, zamiana stron, ponowne wczytanie
/// obu stron (Reload — gdy źródło porównania to umożliwia).
struct DiffViewer: View {
    @State var left: String
    @State var right: String
    @State var leftTitle: String
    @State var rightTitle: String
    var reload: DiffReload? = nil
    @State private var swapped = false
    @State private var reloadError: String?
    @State private var reloading = false
    @State private var options = DiffOptions()
    @State private var rows: [DiffRow] = []
    @State private var current = -1
    @State private var scrollTarget: Int?

    private var changes: [Int] {
        // Pierwsze wiersze bloków zmian.
        rows.indices.filter { rows[$0].kind != .same && ($0 == 0 || rows[$0 - 1].kind == .same) }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                header(leftTitle)
                Divider()
                header(rightTitle)
            }
            .frame(height: 22)
            Divider()
            HStack(spacing: 0) {
                content
                DiffMap(rows: rows) { scrollTarget = $0 }
                    .frame(width: 14)
            }
        }
        .frame(minWidth: 700, minHeight: 400)
        .onAppear(perform: recompute)
        .onChange(of: options) { recompute() }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button { jump(-1) } label: { Image(systemName: "chevron.up") }.iconLabel(L10n.tr("Poprzednia różnica")).disabled(changes.isEmpty)
            Button { jump(1) } label: { Image(systemName: "chevron.down") }.iconLabel(L10n.tr("Następna różnica")).disabled(changes.isEmpty)
            Text(changes.isEmpty ? L10n.tr("Brak różnic") : L10n.tr("Różnica \(max(current, 0) + 1) z \(changes.count)"))
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
            Toggle(L10n.tr("Ignoruj wielkość liter"), isOn: $options.ignoreCase)
            Toggle(L10n.tr("Ignoruj białe znaki"), isOn: $options.ignoreWhitespace)
            Toggle(L10n.tr("Ignoruj komentarze"), isOn: $options.ignoreComments)
            Button(L10n.tr("Zamień strony")) {
                swap(&left, &right)
                swap(&leftTitle, &rightTitle)
                swapped.toggle()
                recompute()
            }
            if let reload {
                Button { runReload(reload) } label: { Image(systemName: "arrow.clockwise") }
                    .iconLabel(L10n.tr("Wczytaj ponownie"))
                    .disabled(reloading)
                    .help(reloadError ?? L10n.tr("Wczytuje ponownie obie strony porównania"))
            }
        }
        .toggleStyle(.checkbox)
        .padding(8)
    }

    private func header(_ t: String) -> some View {
        Text(t).font(.callout.bold()).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8)
    }

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView([.vertical]) {
                LazyVStack(spacing: 0) {
                    ForEach(rows.indices, id: \.self) { i in
                        DiffRowView(row: rows[i]).id(i)
                    }
                }
            }
            .onChange(of: scrollTarget) {
                if let t = scrollTarget { withAnimation { proxy.scrollTo(t, anchor: .center) } }
            }
        }
    }

    private func recompute() {
        rows = TextDiff.rows(left, right, options: options)
        current = -1
        if let first = changes.first { scrollTarget = max(0, first - 3); current = 0 }
    }

    /// Reload: obie strony wczytane ponownie (z zachowaniem zamiany stron i pozycji bieżącej różnicy).
    private func runReload(_ reload: @escaping DiffReload) {
        reloading = true
        Task { @MainActor in
            defer { reloading = false }
            do {
                let (l, r) = try await reload()
                left = swapped ? r : l
                right = swapped ? l : r
                reloadError = nil
                recompute()
            } catch {
                reloadError = error.localizedDescription
            }
        }
    }

    private func jump(_ d: Int) {
        guard !changes.isEmpty else { return }
        current = (current + d + changes.count) % changes.count
        scrollTarget = changes[current]
    }
}

struct DiffRowView: View {
    let row: DiffRow

    var body: some View {
        HStack(spacing: 0) {
            cell(number: row.left, text: row.leftText, change: row.leftChange, side: .left)
            Divider()
            cell(number: row.right, text: row.rightText, change: row.rightChange, side: .right)
        }
        .frame(minHeight: 16)
    }

    enum Side { case left, right }

    private func cell(number: Int?, text: String, change: Range<Int>?, side: Side) -> some View {
        HStack(spacing: 6) {
            Text(number.map(String.init) ?? "")
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(.tertiary).frame(width: 44, alignment: .trailing)
            Text(attributed(text, change: change, side: side))
                .font(.system(size: 12, design: .monospaced)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
        .background(background(side: side, present: number != nil))
    }

    private func background(side: Side, present: Bool) -> Color {
        switch row.kind {
        case .same: .clear
        case .changed: Color.yellow.opacity(0.18)
        case .removed: side == .left ? Color.red.opacity(0.16) : Color.gray.opacity(0.08)
        case .added: side == .right ? Color.green.opacity(0.16) : Color.gray.opacity(0.08)
        }
    }

    private func attributed(_ text: String, change: Range<Int>?, side: Side) -> AttributedString {
        var a = AttributedString(text)
        guard let change, !change.isEmpty else { return a }
        let ns = text as NSString
        let prefix = ns.substring(to: min(change.lowerBound, ns.length))
        let mid = ns.substring(with: NSRange(location: min(change.lowerBound, ns.length), length: min(change.count, ns.length - min(change.lowerBound, ns.length))))
        let start = a.index(a.startIndex, offsetByCharacters: prefix.count)
        let end = a.index(start, offsetByCharacters: mid.count)
        a[start..<end].backgroundColor = side == .left ? Color.red.opacity(0.3) : Color.green.opacity(0.3)
        return a
    }
}

/// Mapa zmian: znaczniki w proporcji do położenia w całym zestawieniu; klik przewija.
struct DiffMap: View {
    let rows: [DiffRow]
    let onSelect: (Int) -> Void

    var body: some View {
        GeometryReader { g in
            Canvas { ctx, size in
                guard !rows.isEmpty else { return }
                let h = size.height / CGFloat(rows.count)
                for (i, r) in rows.enumerated() where r.kind != .same {
                    let color: Color = r.kind == .changed ? .orange : r.kind == .removed ? .red : .green
                    ctx.fill(Path(CGRect(x: 2, y: CGFloat(i) * h, width: size.width - 4, height: max(2, h))), with: .color(color))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { p in
                guard !rows.isEmpty else { return }
                onSelect(min(rows.count - 1, max(0, Int(p.y / g.size.height * CGFloat(rows.count)))))
            }
        }
        .background(Color.gray.opacity(0.06))
        .accessibilityLabel(L10n.tr("Mapa różnic"))
    }
}
