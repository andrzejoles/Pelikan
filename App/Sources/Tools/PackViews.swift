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

/// SQL Monitor (SD-MON-001): monitorowane zapytania, dwuklik — raport.
struct SQLMonitorView: View {
    let workspace: Workspace
    @State private var data: (columns: [String], rows: [[String]]) = ([], [])
    @State private var selection: Int?
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }.iconLabel(L10n.tr("Odśwież"))
                Button(L10n.tr("Raport")) { open(selection) }.disabled(selection == nil)
                Spacer()
                Text(message).font(.uiSecondary).foregroundStyle(.secondary)
            }
            Table(data.rows.indices.map { DetailRow(id: $0, values: data.rows[$0]) }, selection: $selection) {
                TableColumnForEach(data.columns.indices.map { $0 }, id: \.self) { i in
                    TableColumn(data.columns[i]) { (r: DetailRow) in Text(i < r.values.count ? r.values[i] : "").lineLimit(1) }
                }
            }
            .contextMenu(forSelectionType: Int.self) { _ in } primaryAction: { ids in open(ids.first) }
        }
        .padding(10)
        .frame(minWidth: 860, minHeight: 420)
        .task { await reload() }
    }

    private func reload() async {
        guard let conn = workspace.sessions.mainConnectionID else { return }
        do {
            let s = try await workspace.sessions.session(SessionKey(connectionID: conn, purpose: .tool("packs")))
            data = try await ManagementPacks.monitoredSQL(s)
            message = L10n.tr("Zapytania: \(data.rows.count)")
        } catch { message = error.localizedDescription }
    }

    private func open(_ row: Int?) {
        guard let row, row < data.rows.count, let id = data.rows[row].first else { return }
        workspace.perform("tools.sqlMonitorReport", CommandArguments(["sqlId": .string(id)]))
    }
}
