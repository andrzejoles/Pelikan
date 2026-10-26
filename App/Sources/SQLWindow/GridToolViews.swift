import AppKit
import PelikanDB
import PelikanWorkspace
import SwiftUI

/// Wybór zapytania powiązanego (UG 7.4): nadrzędne i podrzędne z kluczy obcych; dwuklik otwiera okno SQL.
struct LinkedQueriesView: View {
    let workspace: Workspace
    let links: [LinkedQuery]
    let values: [String: OracleValue]
    let connection: UUID?
    @State private var selection: LinkedQuery.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            List(links, selection: $selection) { l in
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.title)
                    Text("\(l.constraint): " + l.columns.map { "\($0.0) → \($0.1)" }.joined(separator: ", ")).font(.uiSecondary).foregroundStyle(.secondary)
                }
                .tag(l.id)
            }
            .contextMenu(forSelectionType: LinkedQuery.ID.self) { _ in } primaryAction: { ids in open(ids.first) }
            HStack { Spacer(); Button(L10n.tr("Otwórz")) { open(selection) }.disabled(selection == nil) }
        }
        .padding(10)
        .frame(minWidth: 460, minHeight: 300)
    }

    private func open(_ id: LinkedQuery.ID?) {
        guard let l = links.first(where: { $0.id == id }) else { return }
        let d = workspace.newDocument(.sql, text: l.sql(values: values))
        d.connectionID = connection
        d.isModified = false
        workspace.perform("sql.execute")
        ToolWindowController.close(key: "linkedQueries")
    }
}

/// Porównanie rekordów (UG 7.8): kolumna po kolumnie, różne wyróżnione, filtr „tylko różne”.
struct CompareRecordsView: View {
    let comparison: [GridTools.ColumnComparison]
    @State private var onlyDifferent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(L10n.tr("Tylko różne kolumny"), isOn: $onlyDifferent).toggleStyle(.checkbox)
            let rows = comparison.filter { !onlyDifferent || !$0.identical }
            let n = comparison.first?.values.count ?? 0
            Table(rows) {
                TableColumn(L10n.tr("Kolumna")) { c in Text(c.column).fontWeight(c.identical ? .regular : .semibold) }.width(min: 120, ideal: 160)
                TableColumnForEach(Array(0..<n), id: \.self) { i in
                    TableColumn(L10n.tr("Rekord \(i + 1)")) { (c: GridTools.ColumnComparison) in
                        Text(c.values[i]).foregroundStyle(c.identical ? Color.primary : Color.orange).lineLimit(1)
                    }
                }
            }
            Text(L10n.tr("Różne kolumny: \(comparison.filter { !$0.identical }.count) z \(comparison.count)")).font(.uiSecondary).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(minWidth: 560, minHeight: 360)
    }
}

/// Porównanie wyników (UG 7.9): dwie karty obok siebie (albo jedna nad drugą), różne komórki podświetlone.
struct CompareResultsView: View {
    let left: ResultTab
    let right: ResultTab
    @State private var vertical = false
    @State private var ignoreCase = false

    var body: some View {
        let diff = (left.grid != nil && right.grid != nil) ? GridTools.compareResults(left.grid!, right.grid!, ignoreCase: ignoreCase) : nil
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle(L10n.tr("Jedna nad drugą"), isOn: $vertical)
                Toggle(L10n.tr("Bez wielkości liter"), isOn: $ignoreCase)
                Spacer()
                if let d = diff {
                    Text(d.identical ? L10n.tr("Wyniki identyczne")
                         : L10n.tr("Różne komórki: \(d.cells.count); wiersze tylko po lewej: \(d.rowsOnlyLeft), po prawej: \(d.rowsOnlyRight)"))
                        .font(.uiSecondary)
                }
            }
            .toggleStyle(.checkbox)
            if vertical {
                VSplitView { side(left, diff) ; side(right, diff) }
            } else {
                HSplitView { side(left, diff) ; side(right, diff) }
            }
        }
        .padding(10)
        .frame(minWidth: 820, minHeight: 440)
    }

    private func side(_ tab: ResultTab, _ diff: GridTools.ResultDifference?) -> some View {
        let grid = tab.grid
        let columns = grid?.columns.map(\.name) ?? []
        let rows = (0..<(grid?.rowCount ?? 0)).map { r in DetailRow(id: r, values: columns.indices.map { grid!.text(row: grid!.dataRow(r), column: $0) }) }
        return VStack(alignment: .leading, spacing: 2) {
            Text(tab.title).font(.uiSecondary.bold())
            Table(rows) {
                TableColumnForEach(columns.indices.map { $0 }, id: \.self) { i in
                    TableColumn(columns[i]) { (r: DetailRow) in
                        let different = diff?.cells.contains(.init(row: r.id, column: columns[i].uppercased())) == true
                        Text(r.values[i]).lineLimit(1).padding(.horizontal, 2)
                            .background(different ? Color.orange.opacity(0.35) : Color.clear)
                    }
                }
            }
        }
    }
}

/// Kolumna do plików (UG 7.2): kolumna, szablon nazwy z kolumnami wiersza, katalog.
struct ColumnToFilesView: View {
    let tab: ResultTab
    @State private var column = 0
    @State private var template = "[#].txt"
    @State private var message = ""

    var body: some View {
        let columns = tab.grid?.columns.map(\.name) ?? []
        VStack(alignment: .leading, spacing: 8) {
            Picker(L10n.tr("Kolumna"), selection: $column) { ForEach(columns.indices, id: \.self) { Text(columns[$0]).tag($0) } }
            TextField(L10n.tr("Nazwa pliku (np. [ID]_[NAZWA].txt, [#] — numer wiersza)"), text: $template).textFieldStyle(.roundedBorder)
            Text(L10n.tr("Zaznaczone wiersze albo wszystkie pobrane; LOB-y w pobranej długości.")).font(.uiSecondary).foregroundStyle(.secondary)
            HStack {
                Text(message).font(.uiSecondary)
                Spacer()
                Button(L10n.tr("Zapisz pliki…")) { save() }.disabled(columns.isEmpty || template.isEmpty)
            }
        }
        .padding(12)
        .frame(minWidth: 520, idealWidth: 520, maxWidth: .infinity)
    }

    private func save() {
        guard let grid = tab.grid else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        let rows = tab.selectedRows.flatMap { $0.isEmpty ? nil : $0 } ?? Array(0..<grid.rowCount)
        do {
            let r = try GridTools.columnToFiles(grid, column: column, viewRows: rows, directory: dir, template: template)
            message = L10n.tr("Zapisano plików: \(r.files)") + (r.truncated > 0 ? " " + L10n.tr("(skrócone LOB-y: \(r.truncated))") : "")
        } catch { message = error.localizedDescription }
    }
}
