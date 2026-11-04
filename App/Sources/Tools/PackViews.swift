import AppKit
import PelikanWorkspace
import SwiftUI
import UniformTypeIdentifiers

/// Raport HTML (AWR, ASH, ADDM, SQL Monitor, Tuning Advisor): podgląd bez JavaScriptu i sieci, zapis do pliku.
struct HTMLReportView: View {
    let title: String
    let html: String

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(title).font(.uiHeadline)
                Spacer()
                Button(L10n.tr("Zapisz HTML…")) {
                    let p = NSSavePanel()
                    p.allowedContentTypes = [.html]
                    p.nameFieldStringValue = title.replacingOccurrences(of: " ", with: "_") + ".html"
                    if p.runModal() == .OK, let url = p.url {
                        do { try Data(html.utf8).write(to: url) } catch { NSAlert(error: error).runModal() }
                    }
                }
            }
            HTMLPreview(html: html)
        }
        .padding(8)
        .frame(minWidth: 800, minHeight: 560)
    }
}

/// SQL Monitor (SD-MON-001): monitorowane zapytania, dwuklik — raport. Lista i raporty z połączenia, dla którego
/// komenda sprawdziła licencję Tuning Pack (stałe dla okna).
struct SQLMonitorView: View {
    let workspace: Workspace
    @State private var connection: UUID?
    @State private var data: (columns: [String], rows: [[String]]) = ([], [])
    @State private var selection: Int?
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }.iconLabel(L10n.tr("Odśwież"))
                Button(L10n.tr("Raport")) { open(selection) }.disabled(selection == nil)
                ToolConnectionPicker(workspace: workspace, connection: $connection, editable: false)
                Spacer()
                Text(message).font(.uiSecondary).foregroundStyle(.secondary)
            }
            DataTable(data.rows.indices.map { DetailRow(id: $0, values: data.rows[$0]) }, selection: .single($selection), primaryAction: { ids in open(ids.first) }) {
                for i in data.columns.indices {
                    DataColumn(data.columns[i], id: "\(i)", sortKey: { (r: DetailRow) in i < r.values.count ? r.values[i] : "" }) { (r: DetailRow) in Text(i < r.values.count ? r.values[i] : "").lineLimit(1) }
                }
            }
        }
        .padding(10)
        // Wąski panel doku: tabela przewija kolumny sama, pasek tabeli (Kopiuj, Eksportuj) widoczny.
        .frame(minWidth: 360, minHeight: 420)
        .environment(\.reportConnection, connection)

        .toolTask(id: 0) { await reload() }
    }

    init(workspace: Workspace, connection: UUID) {
        self.workspace = workspace
        _connection = State(initialValue: connection)
    }

    private func reload() async {
        do {
            let s = try await workspace.toolSession("packs", connection: connection)
            data = try await ManagementPacks.monitoredSQL(s)
            message = L10n.tr("Zapytania: \(data.rows.count)")
        } catch { message = error.localizedDescription }
    }

    private func open(_ row: Int?) {
        guard let row, row < data.rows.count, let id = data.rows[row].first, let connection else { return }
        workspace.perform("tools.sqlMonitorReport", CommandArguments(["sqlId": .string(id), "connection": .string(connection.uuidString)]))
    }
}
