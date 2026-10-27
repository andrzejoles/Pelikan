import AppKit
import PelikanDB
import PelikanWorkspace
import SwiftUI

/// Przeglądarka sesji (UG 16, PD-TOOL-015/016): filtr, lista sesji, automatyczne odświeżanie, karty szczegółów
/// zaznaczonej sesji, zabijanie sesji i akcje (SQL Trace), edycja zapytań (Define Session Queries). Lista, szczegóły,
/// zabijanie i akcje na połączeniu okna (ustalonym przy otwarciu) — SID/SERIAL# zawsze z tej samej bazy.
struct SessionBrowserView: View {
    let workspace: Workspace
    @State private var connection: UUID?
    @State private var filter = ""
    @State private var rows: [SessionRow] = []
    @State private var selection: SessionRow.ID?
    @State private var detailName = ""
    @State private var detail: SessionBrowser.Detail?
    @State private var message = ""
    @State private var autoRefresh = false
    @State private var interval = 10.0
    @State private var editing = false

    private let shown = ["SID", "SERIAL#", "USERNAME", "STATUS", "OSUSER", "MACHINE", "PROGRAM", "MODULE", "ACTION", "SQL_ID", "EVENT", "LOGON_TIME"]
    private var queries: SessionQueries { workspace.settings.sessionQueries }
    private var selected: SessionRow? { rows.first { $0.id == selection } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ToolConnectionPicker(workspace: workspace, connection: $connection)
                Picker(L10n.tr("Filtr"), selection: $filter) {
                    ForEach(queries.filters) { Text($0.name).tag($0.sql) }
                }
                .frame(maxWidth: 260)
                Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }.iconLabel(L10n.tr("Odśwież"))
                Toggle(L10n.tr("Odświeżaj co"), isOn: $autoRefresh).toggleStyle(.checkbox)
                Stepper("\(Int(interval)) s", value: $interval, in: 2...300, step: 1).fixedSize()
                Spacer()
                Button(L10n.tr("Zabij")) { kill(immediate: false) }.disabled(selected == nil)
                Button(L10n.tr("Zabij natychmiast")) { kill(immediate: true) }.disabled(selected == nil)
                Menu(L10n.tr("Akcje")) {
                    ForEach(queries.actions) { a in Button(a.name) { perform(a) } }
                }
                .fixedSize()
                .disabled(selected == nil)
                Button(L10n.tr("Zapytania…")) { editing = true }
            }
            VSplitView {
                Table(rows, selection: $selection) {
                    TableColumnForEach(shown, id: \.self) { name in
                        TableColumn(name) { (r: SessionRow) in Text(r.values[name] ?? "").lineLimit(1) }
                    }
                }
                .frame(minHeight: 160)
                VStack(alignment: .leading, spacing: 4) {
                    Picker("", selection: $detailName) {
                        ForEach(queries.details) { Text($0.name).tag($0.name) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    detailView
                }
                .frame(minHeight: 120)
            }
            Text(message).font(.uiSecondary).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(minWidth: 900, minHeight: 520)
        .toolTask(id: 0) {
            filter = queries.filters.first { $0.sql == "type = 'USER'" }?.sql ?? queries.filters.first?.sql ?? ""
            detailName = queries.details.first?.name ?? ""
            await reload()
        }
        .task(id: autoRefresh ? interval : 0) {
            guard autoRefresh else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                await reload()
            }
        }
        .onChange(of: filter) { Task { await reload() } }
        .onChange(of: connection) {
            selection = nil
            Task { await reload() }
        }
        .onChange(of: selection) { Task { await loadDetail() } }
        .onChange(of: detailName) { Task { await loadDetail() } }
        .sheet(isPresented: $editing) { SessionQueriesEditor(workspace: workspace, done: { editing = false }) }
    }

    init(workspace: Workspace) {
        self.workspace = workspace
        _connection = State(initialValue: workspace.toolConnection())
    }

    private func session() async throws -> any DatabaseSession {
        try await workspace.toolSession("sessions", connection: connection)
    }

    @ViewBuilder private var detailView: some View {
        if let d = detail {
            if let text = d.text {
                ScrollView { Text(text).font(.code).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            } else {
                Table(d.rows.indices.map { DetailRow(id: $0, values: d.rows[$0]) }) {
                    TableColumnForEach(d.columns.indices.map { $0 }, id: \.self) { i in
                        TableColumn(d.columns[i]) { (r: DetailRow) in Text(i < r.values.count ? r.values[i] : "").lineLimit(1) }
                    }
                }
            }
        } else {
            Text(L10n.tr("Zaznacz sesję")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func reload() async {
        do {
            let s = try await session()
            rows = try await SessionBrowser.list(filter: filter, in: s)
            message = L10n.tr("Sesje: \(rows.count)")
            await loadDetail()
        } catch { message = error.localizedDescription }
    }

    private func loadDetail() async {
        guard let r = selected, let item = queries.details.first(where: { $0.name == detailName }) else { detail = nil; return }
        do {
            detail = try await SessionBrowser.detail(item, sid: r.sid, serial: r.serial, in: try await session())
        } catch { message = error.localizedDescription; detail = nil }
    }

    private func kill(immediate: Bool) {
        guard let r = selected, let connection else { return }
        Task {
            do {
                try await workspace.invoke("sessions.kill", CommandArguments(["sid": .int(Int64(r.sid)), "serial": .int(Int64(r.serial)), "immediate": .bool(immediate),
                                                                               "connection": .string(connection.uuidString)]))
                await reload()
            } catch CommandError.cancelledByUser {
            } catch { message = error.localizedDescription }
        }
    }

    private func perform(_ a: SessionQueries.Item) {
        guard let r = selected, let connection else { return }
        Task {
            do {
                try await workspace.invoke("sessions.action", CommandArguments(["sid": .int(Int64(r.sid)), "serial": .int(Int64(r.serial)), "action": .string(a.name),
                                                                                 "connection": .string(connection.uuidString)]))
                message = L10n.tr("Wykonano: \(a.name)")
            } catch CommandError.cancelledByUser {
            } catch { message = error.localizedDescription }
        }
    }
}

struct DetailRow: Identifiable {
    let id: Int
    let values: [String]
}

/// Edycja zapytań przeglądarki sesji (UG 16.2).
struct SessionQueriesEditor: View {
    let workspace: Workspace
    let done: () -> Void
    @State private var queries = SessionQueries.standard
    @State private var section = 0
    @State private var selected: String?

    private var items: Binding<[SessionQueries.Item]> {
        switch section {
        case 0: $queries.filters
        case 1: $queries.details
        default: $queries.actions
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $section) {
                Text(L10n.tr("Filtry (warunek WHERE)")).tag(0)
                Text(L10n.tr("Szczegóły (:sid, /* concatenate */)")).tag(1)
                Text(L10n.tr("Akcje (:sid, :serial#)")).tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            List {
                ForEach(items) { $item in
                    VStack(alignment: .leading, spacing: 2) {
                        TextField(L10n.tr("Nazwa"), text: $item.name).font(.uiHeadline)
                        TextField("SQL", text: $item.sql, axis: .vertical).font(.code).lineLimit(1...4)
                    }
                }
                .onDelete { items.wrappedValue.remove(atOffsets: $0) }
            }
            HStack {
                Button(L10n.tr("Dodaj")) { items.wrappedValue.append(SessionQueries.Item(name: L10n.tr("Nowe"), sql: "")) }
                Button(L10n.tr("Domyślne")) { queries = .standard }
                Spacer()
                Button(L10n.tr("Anuluj"), role: .cancel) { done() }.keyboardShortcut(.cancelAction)
                Button(L10n.tr("Zapisz")) {
                    workspace.settings.sessionQueries = queries
                    done()
                }
            }
        }
        .padding(14)
        .windowSize(width: 720, height: 460)
        .onAppear { queries = workspace.settings.sessionQueries }
    }
}
