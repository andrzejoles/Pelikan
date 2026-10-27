import AppKit
import PelikanDB
import PelikanWorkspace
import SwiftUI

/// Narzędzie SwiftUI w panelu okna głównego albo w osobnym oknie (miejsce wg Preferencji, D183); jedno narzędzie
/// danego rodzaju — ponowne wywołanie je przywołuje.
@MainActor
enum ToolWindowController {
    static func show<V: View>(key: String, title: String, size: NSSize, @ViewBuilder content: () -> V) {
        let manager = ToolDockManager.shared
        if manager.reveal(key: key) { return }
        let lifetime = ToolLifetime()
        let view = NSHostingView(rootView: AnyView(content().interfaceFont().environment(\.toolLifetime, lifetime)))
        manager.show(key: key, title: title, size: size, content: view, lifetime: lifetime)
    }

    /// Zamyka narzędzie o danym kluczu (np. przed pokazaniem nowej zawartości).
    static func close(key: String) {
        ToolDockManager.shared.close(key: key)
    }
}

/// Połączenie okna narzędzia: ustalone przy otwarciu (`Workspace.toolConnection()` — aktywne okno albo główne),
/// widoczne w oknie i zmieniane tylko tutaj; wszystkie operacje okna używają go zamiast aktywnego okna z chwili kliknięcia.
/// `editable: false` — tylko nazwa (okno związane ze sprawdzoną licencją, np. SQL Monitor).
struct ToolConnectionPicker: View {
    let workspace: Workspace
    @Binding var connection: UUID?
    var editable = true

    var body: some View {
        if editable {
            Picker(L10n.tr("Połączenie"), selection: $connection) {
                if connection == nil { Text(L10n.tr("(brak)")).tag(UUID?.none) }
                ForEach(workspace.connections.connections) { Text($0.displayName).tag(UUID?.some($0.id)) }
            }
            .fixedSize()
        } else {
            Text(L10n.tr("Połączenie: \(connection.flatMap { workspace.connections.connection($0)?.displayName } ?? L10n.tr("(brak)"))"))
                .font(.uiSecondary).foregroundStyle(.secondary)
        }
    }
}

/// Find Database Objects (UG 24.2): kryteria, wyszukiwanie w tle, wyniki z przejściem do linii źródła.
struct FindObjectsView: View {
    let workspace: Workspace
    @State var criteria: DatabaseSearchCriteria
    @State private var owner = ""
    @State private var hits: [DatabaseSearchHit] = []
    @State private var running = false
    @State private var task: Task<Void, Never>?
    @State private var message = ""
    @State private var selection: DatabaseSearchHit.ID?
    @FocusState private var textFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            criteriaForm
            resultsTable
            footer
        }
        .padding(12)
        .frame(minWidth: 620, minHeight: 380)
        .onFirstAppear {
            owner = criteria.owners.joined(separator: ", ")
            textFocused = true
        }
        // Zamknięcie narzędzia przerywa wyszukiwanie (inaczej zajmowałoby sesję metadanych nawet przez minuty).
        .onToolClose { task?.cancel() }
    }

    private var criteriaForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField(L10n.tr("Szukany tekst"), text: $criteria.text).onSubmit { if !running { run() } }.focused($textFocused)
                Button(running ? L10n.tr("Przerwij") : L10n.tr("Szukaj")) { if running { cancel() } else { run() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!running && criteria.text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack(spacing: 14) {
                Toggle(L10n.tr("Wielkość liter"), isOn: $criteria.caseSensitive)
                Toggle(L10n.tr("Całe słowa"), isOn: $criteria.wholeWords)
                Toggle(L10n.tr("Wyrażenie regularne"), isOn: $criteria.regularExpression)
                Toggle(L10n.tr("Nazwy obiektów"), isOn: $criteria.searchNames)
                Toggle(L10n.tr("Definicje tabel"), isOn: $criteria.searchTableDefinitions)
                    .help(L10n.tr("Nazwy i komentarze kolumn, komentarze tabel, warunki CHECK"))
            }
            .toggleStyle(.checkbox)
            HStack {
                TextField(L10n.tr("Właściciele (po przecinku; puste — bieżący)"), text: $owner)
                TextField(L10n.tr("Nazwa obiektu (%)"), text: $criteria.nameFilter)
                typesMenu
                savedMenu
            }
        }
    }

    /// Typy obiektów (puste — wszystkie źródła i widoki).
    private var typesMenu: some View {
        Menu(criteria.types.isEmpty ? L10n.tr("Wszystkie typy") : L10n.tr("Typy: \(criteria.types.count)")) {
            Button(L10n.tr("Wszystkie typy")) { criteria.types = [] }
            Divider()
            ForEach(DatabaseSearch.selectableTypes, id: \.self) { t in
                Toggle(t.rawValue, isOn: Binding(get: { criteria.types.contains(t) },
                                                 set: { on in if on { criteria.types.append(t) } else { criteria.types.removeAll { $0 == t } } }))
            }
        }
        .fixedSize()
    }

    /// Zapisane kryteria (PD-TOOL-001): wczytanie, zapis bieżących, usunięcie.
    private var savedMenu: some View {
        Menu(L10n.tr("Kryteria")) {
            ForEach(workspace.settings.savedDatabaseSearches) { s in
                Button(s.name) {
                    criteria = s.criteria
                    owner = s.criteria.owners.joined(separator: ", ")
                }
            }
            if !workspace.settings.savedDatabaseSearches.isEmpty { Divider() }
            Button(L10n.tr("Zapisz bieżące…")) { saveCriteria() }
            if !workspace.settings.savedDatabaseSearches.isEmpty {
                Menu(L10n.tr("Usuń")) {
                    ForEach(workspace.settings.savedDatabaseSearches) { s in
                        Button(s.name) { workspace.perform("tools.deleteObjectSearch", CommandArguments(["saved": .string(s.name)])) }
                    }
                }
            }
        }
        .fixedSize()
    }

    private func saveCriteria() {
        Task {
            guard let name = await workspace.ui?.askText(L10n.tr("Zapisz kryteria wyszukiwania"), message: L10n.tr("Nazwa"), defaultValue: criteria.text),
                  !name.isEmpty else { return }
            var args: [String: JSONValue] = ["saveAs": .string(name), "text": .string(criteria.text), "caseSensitive": .bool(criteria.caseSensitive),
                                             "wholeWords": .bool(criteria.wholeWords), "regex": .bool(criteria.regularExpression),
                                             "owner": .string(owner), "name": .string(criteria.nameFilter), "names": .bool(criteria.searchNames),
                                             "tableDefinitions": .bool(criteria.searchTableDefinitions)]
            if !criteria.types.isEmpty { args["types"] = .string(criteria.types.map(\.rawValue).joined(separator: ",")) }
            workspace.perform("tools.saveObjectSearch", CommandArguments(args))
        }
    }

    private var resultsTable: some View {
        Table(hits, selection: $selection) {
            TableColumn(L10n.tr("Obiekt")) { (h: DatabaseSearchHit) in Text(h.object.owner + "." + h.object.name) }.width(min: 140, ideal: 200)
            TableColumn(L10n.tr("Typ")) { (h: DatabaseSearchHit) in Text(h.object.type.rawValue.lowercased()) }.width(min: 70, ideal: 100)
            TableColumn(L10n.tr("Linia")) { (h: DatabaseSearchHit) in Text(h.line > 0 ? String(h.line) : "") }.width(min: 40, ideal: 50)
            TableColumn(L10n.tr("Tekst")) { (h: DatabaseSearchHit) in Text(h.text).font(.code).lineLimit(1) }
        }
        .contextMenu(forSelectionType: DatabaseSearchHit.ID.self) { _ in } primaryAction: { ids in
            if let id = ids.first, let h = hits.first(where: { $0.id == id }) { open(h) }
        }
    }

    private var footer: some View {
        HStack {
            if running { ProgressView().controlSize(.small) }
            Text(message).foregroundStyle(.secondary).font(.ui)
            Spacer()
            Button(L10n.tr("Eksportuj CSV…")) { exportResults() }.disabled(hits.isEmpty)
            Button(L10n.tr("Kopiuj wyniki")) { copyResults() }.disabled(hits.isEmpty)
        }
    }

    private func run() {
        // Jedno wyszukiwanie naraz: Enter w polu w trakcie wyszukiwania nie uruchamia drugiego.
        guard !running else { return }
        guard let m = workspace.metadata() else { message = L10n.tr("Brak połączenia głównego"); return }
        var c = criteria
        c.owners = owner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }.filter { !$0.isEmpty }
        running = true
        message = L10n.tr("Wyszukiwanie…")
        task?.cancel()
        task = Task {
            do {
                let r = try await DatabaseSearch.search(c, metadata: m)
                guard !Task.isCancelled else { return }
                hits = r
                message = L10n.tr("Znaleziono: \(r.count)")
            } catch is CancellationError {
                message = L10n.tr("Przerwano")
            } catch {
                guard !Task.isCancelled else { return }
                message = error.localizedDescription
            }
            running = false
        }
    }

    private func cancel() {
        task?.cancel()
        running = false
        message = L10n.tr("Przerwano")
    }

    private func open(_ h: DatabaseSearchHit) {
        Task {
            do { try await workspace.openObject(h.object, line: h.line) } catch { workspace.ui?.showError(error.localizedDescription) }
            NSApp.mainWindow?.makeKeyAndOrderFront(nil)
        }
    }

    private func exportResults() {
        let data = Data(DatabaseSearch.exportText(hits, csv: true).utf8)
        Task { _ = await workspace.ui?.saveFile(suggestedName: L10n.tr("wyniki-wyszukiwania"), fileExtension: "csv", data: data) }
    }

    private func copyResults() {
        let text = hits.map { "\($0.object.owner).\($0.object.name)\t\($0.object.type.rawValue)\t\($0.line)\t\($0.text)" }.joined(separator: "\n")
        workspace.ui?.copyToClipboard(text, html: nil)
    }
}

/// Compile Invalid Objects (UG 24.3): lista nieprawidłowych obiektów, kompilacja, błędy.
struct CompileInvalidView: View {
    let workspace: Workspace
    @State private var owner = ""
    @State private var objects: [DBObject] = []
    @State private var results: [String: InvalidObjectResult] = [:]
    @State private var running = false
    @State private var progress = 0.0
    @State private var message = ""
    @State private var selection: DBObject.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField(L10n.tr("Właściciel (puste — bieżący schemat)"), text: $owner).onSubmit { refresh() }
                Button(L10n.tr("Odśwież")) { refresh() }.disabled(running)
                Button(L10n.tr("Kompiluj wszystkie")) { compile() }.keyboardShortcut(.defaultAction).disabled(running || objects.isEmpty)
            }
            objectsTable
            HStack {
                if running { ProgressView(value: progress).frame(width: 160) }
                Text(message).foregroundStyle(.secondary).font(.ui)
            }
        }
        .padding(12)
        .frame(minWidth: 560, minHeight: 340)
        .onAppear { refresh() }
    }

    private var objectsTable: some View {
        Table(objects, selection: $selection) {
            TableColumn(L10n.tr("Obiekt")) { (o: DBObject) in Text(o.owner + "." + o.name) }.width(min: 160, ideal: 220)
            TableColumn(L10n.tr("Typ")) { (o: DBObject) in Text(o.type.rawValue.lowercased()) }.width(min: 80, ideal: 110)
            TableColumn(L10n.tr("Wynik")) { (o: DBObject) in resultCell(o) }
        }
        .contextMenu(forSelectionType: DBObject.ID.self) { _ in } primaryAction: { ids in
            if let id = ids.first, let o = objects.first(where: { $0.id == id }) {
                Task { try? await workspace.openObject(o) }
            }
        }
    }

    @ViewBuilder private func resultCell(_ o: DBObject) -> some View {
        if let r = results[o.id] {
            Text(r.valid ? L10n.tr("poprawny") : r.errors.first ?? L10n.tr("błędy"))
                .foregroundStyle(r.valid ? Color.green : Color.red).lineLimit(1).help(r.errors.joined(separator: "\n"))
        } else {
            Text(o.status.lowercased()).foregroundStyle(.secondary)
        }
    }

    private func refresh() {
        guard let m = workspace.metadata() else { message = L10n.tr("Brak połączenia głównego"); return }
        Task {
            do {
                var o = owner.trimmingCharacters(in: .whitespaces).uppercased()
                if o.isEmpty { o = try await m.currentSchema() }
                objects = try await InvalidObjects.list(m, owner: o)
                results = [:]
                message = L10n.tr("Nieprawidłowe obiekty: \(objects.count)")
            } catch { message = error.localizedDescription }
        }
    }

    private func compile() {
        guard let m = workspace.metadata() else { return }
        running = true
        progress = 0
        Task {
            do {
                let r = try await InvalidObjects.compile(objects, in: workspace, connectionID: m.connectionID) { done, total in
                    progress = Double(done) / Double(max(total, 1))
                }
                results = Dictionary(uniqueKeysWithValues: r.map { ($0.id, $0) })
                let bad = r.filter { !$0.valid }.count
                message = L10n.tr("Skompilowano: \(r.count - bad) z \(r.count)")
            } catch CommandError.cancelledByUser {
                message = L10n.tr("Anulowano")
            } catch { message = error.localizedDescription }
            running = false
        }
    }
}
