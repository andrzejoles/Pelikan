import AppKit
import PelikanDB
import PelikanWorkspace
import SwiftUI

/// Okno narzędzia (SwiftUI w niemodalnym oknie); jedno okno danego rodzaju — ponowne wywołanie je przywołuje.
@MainActor
final class ToolWindowController: NSWindowController, NSWindowDelegate {
    private static var open: [String: ToolWindowController] = [:]
    private let key: String
    private static let transientPrefixes = ["diff-", "table-", "graph-", "spatial-", "debugger-", "html-"]

    static func show<V: View>(key: String, title: String, size: NSSize, @ViewBuilder content: () -> V) {
        if let c = open[key] { c.showWindow(nil); c.window?.makeKeyAndOrderFront(nil); return }
        let c = ToolWindowController(key: key, title: title, size: size, view: AnyView(content()))
        open[key] = c
        c.showWindow(nil)
    }

    /// Zamyka okno o danym kluczu (np. przed pokazaniem nowej zawartości).
    static func close(key: String) {
        open[key]?.close()
        open[key] = nil
    }

    init(key: String, title: String, size: NSSize, view: AnyView) {
        self.key = key
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.title = title
        w.contentView = NSHostingView(rootView: view.interfaceFont())
        w.center()
        // Okna z kluczem jednorazowym (UUID, id dokumentu) bez zapamiętanej ramki — każde zostawiałoby wpis w UserDefaults.
        if !Self.transientPrefixes.contains(where: key.hasPrefix) { w.setFrameAutosaveName("Pelikan.\(key)") }
        super.init(window: w)
        w.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func windowWillClose(_ notification: Notification) { Self.open[key] = nil }
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
        .onAppear {
            owner = criteria.owners.joined(separator: ", ")
            textFocused = true
        }
    }

    private var criteriaForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField(L10n.tr("Szukany tekst"), text: $criteria.text).onSubmit { run() }.focused($textFocused)
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
            TableColumn(L10n.tr("Tekst")) { (h: DatabaseSearchHit) in Text(h.text).font(.system(size: 12, design: .monospaced)).lineLimit(1) }
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
        guard let m = workspace.metadata() else { message = L10n.tr("Brak połączenia głównego"); return }
        var c = criteria
        c.owners = owner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }.filter { !$0.isEmpty }
        running = true
        message = L10n.tr("Wyszukiwanie…")
        task = Task {
            do {
                let r = try await DatabaseSearch.search(c, metadata: m)
                hits = r
                message = L10n.tr("Znaleziono: \(r.count)")
            } catch is CancellationError {
                message = L10n.tr("Przerwano")
            } catch {
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
