import AppKit
import PelikanDB
import PelikanWorkspace
import SwiftUI

/// Eksplorator testów utPLSQL (UT-EXP-001): suity, konteksty i testy bieżącego użytkownika z ostatnim wynikiem;
/// przeładowanie po kompilacji; dwuklik otwiera adnotację w specyfikacji pakietu testowego. Połączenie ustalone przy
/// otwarciu (aktywne okno albo główne, D182/D185): lista, uruchomienie i otwarcie źródła dotyczą tej samej bazy.
struct TestExplorerView: View {
    let workspace: Workspace
    @State private var connection: UUID?
    @State private var items: [UtSuiteItem] = []
    @State private var message = ""
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button { workspace.perform("utplsql.runAll", connectionArguments()) } label: { Label(L10n.tr("Wszystkie"), systemImage: "play.fill") }
                Button { runSelected(coverage: false) } label: { Label(L10n.tr("Zaznaczone"), systemImage: "play") }.disabled(selection == nil)
                Button { runSelected(coverage: true) } label: { Label(L10n.tr("Z pokryciem"), systemImage: "chart.bar") }.disabled(selection == nil)
                Spacer()
                ToolConnectionPicker(workspace: workspace, connection: $connection)
                Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }.iconLabel(L10n.tr("Odśwież"))
            }
            List(selection: $selection) {
                ForEach(items) { ExplorerRow(item: $0, workspace: workspace) }
            }
            .contextMenu(forSelectionType: String.self) { _ in
                Button(L10n.tr("Uruchom")) { runSelected(coverage: false) }
                Button(L10n.tr("Uruchom z pokryciem")) { runSelected(coverage: true) }
            } primaryAction: { ids in
                if let id = ids.first, let i = find(id) { open(i) }
            }
            Text(message).font(.uiSecondary).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(minWidth: 380, minHeight: 360)
        // Raz dla połączenia: przeniesienie narzędzia między panelem a oknem nie wczytuje listy od nowa.
        .toolTask(id: connection) { await reload() }
        .onChange(of: workspace.compileGeneration) { Task { await reload() } }
    }

    init(workspace: Workspace) {
        self.workspace = workspace
        _connection = State(initialValue: workspace.toolConnection())
    }

    /// Argumenty komend przebiegu: połączenie eksploratora, nie aktywnego okna z chwili kliknięcia.
    private func connectionArguments(_ args: [String: JSONValue] = [:]) -> CommandArguments {
        UtNodeRow.arguments(args, connection: connection)
    }

    private func reload() async {
        guard let m = workspace.metadata(for: connection) else { items = []; message = L10n.tr("Brak połączenia"); return }
        do {
            items = try await UtplsqlExplorer.load(owner: try await m.currentSchema(), metadata: m)
            func count(_ n: [UtSuiteItem]) -> Int { n.reduce(0) { $0 + ($1.kind == .test ? 1 : count($1.children ?? [])) } }
            message = L10n.tr("Testy: \(count(items))")
        } catch { message = error.localizedDescription }
    }

    private func find(_ id: String) -> UtSuiteItem? {
        func f(_ n: [UtSuiteItem]) -> UtSuiteItem? {
            for x in n { if x.id == id { return x }; if let y = f(x.children ?? []) { return y } }
            return nil
        }
        return f(items)
    }

    private func runSelected(coverage: Bool) {
        guard let id = selection, let i = find(id) else { return }
        workspace.perform("utplsql.runPath", connectionArguments(["path": .string(i.runPath), "coverage": .bool(coverage)]))
    }

    private func open(_ i: UtSuiteItem) {
        guard i.kind != .logicalSuite else { return }
        let connection = connection
        Task {
            try? await workspace.openObject(DBObject(owner: i.owner, name: i.object, type: .package), line: i.line, connection: connection)
            ToolWindowController.showMainWindow()
        }
    }
}

struct ExplorerRow: View {
    let item: UtSuiteItem
    let workspace: Workspace
    @State private var expanded = true

    var body: some View {
        if let c = item.children, !c.isEmpty {
            DisclosureGroup(isExpanded: $expanded) {
                ForEach(c) { ExplorerRow(item: $0, workspace: workspace) }
            } label: { label }
        } else {
            label
        }
    }

    /// Ostatni wynik elementu z bieżącego przebiegu (ścieżki identyczne jak w raporcie).
    private var status: UtStatus? {
        func find(_ n: [UtNode]) -> UtNode? {
            for x in n { if x.id == item.path { return x }; if let y = find(x.children ?? []) { return y } }
            return nil
        }
        return workspace.lastUtplsqlRun.flatMap { find($0.roots)?.status }
    }

    private var label: some View {
        HStack(spacing: 6) {
            Image(systemName: item.kind == .test ? (status.map(UtNodeRow.icon) ?? "circle") : item.kind == .logicalSuite ? "folder" : "shippingbox")
                .foregroundStyle(status.map(UtNodeRow.color) ?? .secondary)
            Text(item.title).lineLimit(1).foregroundStyle(item.disabled ? .secondary : .primary)
            if item.disabled { Text(L10n.tr("wyłączony")).font(.uiSecondary).foregroundStyle(.secondary) }
        }
        .tag(item.id)
        .help(item.path)
    }
}
