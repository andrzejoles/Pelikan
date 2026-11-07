import AppKit
import PelikanDB
import PelikanWorkspace
import SwiftUI
import WebKit

/// Panel wartości obok siatki (DB-PANEL-001): bieżąca komórka jako tekst, JSON, XML, HTML, obraz albo hex.
/// Obcięty CLOB/NCLOB jest dociągany w całości od razu (lokator ze sterownika), BLOB — tylko na żądanie
/// („Pobierz całość”, „Zapisz do pliku…”).
struct CellValuePanelView: View {
    let workspace: Workspace
    @Bindable var tab: ResultTab
    let grid: ResultGridModel
    @State private var mode: CellValuePresentation.Mode?
    /// Pełna treść obciętego LOB-a bieżącej komórki (klucz komórki, wartość).
    @State private var full: (key: String, value: LOBValue)?
    @State private var loading: String?
    @State private var loadError: String?
    @State private var requested: String?

    private var cell: (row: Int, column: Int)? {
        guard let row = tab.selectedRows?.first, let col = tab.currentColumn, row < grid.rowCount, col < grid.columns.count else { return nil }
        return (row, col)
    }

    private var lob: LOBValue? {
        guard let c = cell, case .lob(let l) = grid.value(row: c.row, column: c.column) else { return nil }
        return l
    }

    /// Klucz komórki: wiersz, kolumna i lokator (po ponownym wykonaniu ta sama komórka ma inny lokator).
    private var key: String {
        guard let c = cell else { return "" }
        return "\(c.row):\(c.column):\(lob?.locator?.id ?? 0)"
    }

    private var isText: Bool { lob.map { $0.kind == .clob || $0.kind == .nclob } ?? false }

    private var presentation: CellValuePresentation? {
        guard let c = cell else { return nil }
        var v = grid.value(row: c.row, column: c.column)
        if let f = full, f.key == key { v = .lob(f.value) }
        else if let l = lob, let cached = grid.cachedFullLOB(l) { v = .lob(cached) }
        return CellValuePresentation.make(v, column: grid.columns[c.column], format: grid.format)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let p = presentation {
                HStack {
                    Text(p.column).font(.uiSecondary.bold()).lineLimit(1)
                    Text(p.typeName).font(.uiSecondary).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Picker("", selection: Binding(get: { mode.flatMap { p.modes.contains($0) ? $0 : nil } ?? p.detected }, set: { mode = $0 })) {
                        ForEach(p.modes, id: \.self) { Text(label($0)).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                if let l = lob {
                    HStack(spacing: 6) {
                        Text(sizeText(l)).font(.uiSecondary).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        if p.truncated, !isText, l.locator != nil, loading != key {
                            Button(L10n.tr("Pobierz całość")) { requested = key }
                                .help(L10n.tr("Pobiera całą wartość binarną z bazy do podglądu"))
                        }
                        Button { _ = workspace.perform("grid.saveValue", target: tab) } label: { Image(systemName: "square.and.arrow.down") }
                            .iconLabel(L10n.tr("Zapisz wartość komórki do pliku…"))
                        Button { _ = workspace.perform("grid.openValueExternally", target: tab) } label: { Image(systemName: "arrow.up.forward.app") }
                            .iconLabel(L10n.tr("Otwórz wartość komórki w programie zewnętrznym"))
                    }
                    .controlSize(.small)
                }
                if loading == key {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(L10n.tr("Pobieranie pełnej wartości…")).font(.uiSecondary).foregroundStyle(.secondary)
                    }
                } else if let e = loadError {
                    Text(e).font(.uiSecondary).foregroundStyle(.red)
                } else if p.truncated {
                    Text(lob?.locator == nil ? L10n.tr("Wartość obcięta do pobranej długości — pełna w Large Data Editor")
                                             : L10n.tr("Podgląd początku wartości — całość: „Pobierz całość” albo zapis do pliku"))
                        .font(.uiSecondary).foregroundStyle(.orange)
                }
                content(p, mode.flatMap { p.modes.contains($0) ? $0 : nil } ?? p.detected)
            } else {
                Text(L10n.tr("Zaznacz komórkę")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(6)
        .background(Color(nsColor: .controlBackgroundColor))
        .task(id: key + "|" + (requested == key ? "load" : "")) { await loadIfNeeded() }
    }

    /// Tekst LOB-a — od razu w całości; binarny — po „Pobierz całość”.
    private func loadIfNeeded() async {
        let k = key
        loadError = nil
        guard let l = lob, l.truncated, l.locator != nil, full?.key != k else { return }
        if let cached = grid.cachedFullLOB(l) { full = (k, cached); return }
        guard isText || requested == k else { return }
        loading = k
        defer { if loading == k { loading = nil } }
        do {
            let v = try await grid.fullLOB(l)
            guard key == k else { return }
            full = (k, v)
        } catch is CancellationError {
        } catch {
            if key == k { loadError = error.localizedDescription }
        }
    }

    private func sizeText(_ l: LOBValue) -> String {
        let n = ByteCountFormatter.string(fromByteCount: Int64(l.length), countStyle: .file)
        return l.kind == .clob || l.kind == .nclob ? L10n.tr("\(l.length) znaków") : n
    }

    private func label(_ m: CellValuePresentation.Mode) -> String {
        switch m {
        case .text: L10n.tr("Tekst")
        case .json: "JSON"
        case .xml: "XML"
        case .html: "HTML"
        case .image: L10n.tr("Obraz")
        case .preview: L10n.tr("Podgląd")
        case .hex: "Hex"
        }
    }

    @ViewBuilder private func content(_ p: CellValuePresentation, _ m: CellValuePresentation.Mode) -> some View {
        switch m {
        case .image:
            if let d = p.data, let img = NSImage(data: d) {
                Image(nsImage: img).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(L10n.tr("Nie można odczytać obrazu")).foregroundStyle(.secondary)
            }
        case .html:
            HTMLPreview(html: p.text)
        case .preview:
            if let d = p.data, !p.truncated {
                QuickLookPreview(data: d, format: p.format, id: "\(key)|\(d.count)")
            } else {
                Text(L10n.tr("Podgląd po pobraniu całej wartości — „Pobierz całość”")).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        default:
            ReadOnlyTextView(text: p.rendered(m), id: "\(key)|\(m.rawValue)|\(p.text.utf16.count)|\(p.data?.count ?? 0)")
        }
    }
}

/// Tekst tylko do odczytu w NSTextView (zaznaczanie, szukanie ⌘F, przewijanie) — wydajny także dla wielu MB, w
/// przeciwieństwie do `Text` w SwiftUI. Treść podmieniana tylko przy zmianie `id` (bez porównywania całego tekstu).
struct ReadOnlyTextView: NSViewRepresentable {
    let text: String
    let id: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.isEditable = false
        tv.isSelectable = true
        tv.isRichText = false
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.layoutManager?.allowsNonContiguousLayout = true
        tv.font = InterfaceFonts.shared.code
        tv.textContainerInset = NSSize(width: 2, height: 4)
        scroll.hasHorizontalScroller = true
        tv.isHorizontallyResizable = true
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.string = text
        context.coordinator.id = id
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard context.coordinator.id != id, let tv = scroll.documentView as? NSTextView else { return }
        context.coordinator.id = id
        tv.string = text
        tv.scroll(.zero)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var id = "" }
}

/// Podgląd HTML bez JavaScriptu i bez sieci (treść z bazy jest niezaufana).
struct HTMLPreview: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView { WKWebView.localHTML() }

    func updateNSView(_ view: WKWebView, context: Context) {
        view.loadHTMLString(LargeDataModel.htmlPreviewDocument(html), baseURL: nil)
    }
}

/// Grupowanie z licznikami (DB-GRID-001): dwuklik filtruje siatkę po wartości.
struct GroupCountsView: View {
    let workspace: Workspace
    let tab: ResultTab
    let column: Int
    let counts: [GroupCount]
    @State private var selection: GroupCount.ID?

    var body: some View {
        let name = tab.grid?.columns[column].name ?? ""
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.tr("Kolumna \(name): różnych wartości \(counts.count)")).font(.uiSecondary)
            DataTable(counts, selection: .single($selection), primaryAction: { ids in
                if let id = ids.first, let g = counts.first(where: { $0.id == id }) { apply(g) }
            }) {
                DataColumn(L10n.tr("Wartość"), sortKey: { g in g.value }) { g in Text(g.value).foregroundStyle(g.isNull ? .secondary : .primary) }
                DataColumn(L10n.tr("Liczba"), sortKey: { g in g.count }) { g in Text("\(g.count)").monospacedDigit() }.width(70)
            }
            Text(L10n.tr("Dwukrotne kliknięcie — pokaż w siatce tylko wiersze z tą wartością.")).font(.uiSecondary).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(minWidth: 360, minHeight: 300)
    }

    private func apply(_ g: GroupCount) {
        guard let grid = tab.grid else { return }
        let name = grid.columns[column].name
        let quoted = "'" + g.value.replacingOccurrences(of: "'", with: "''") + "'"
        let expr = g.isNull ? "\"\(name)\" IS NULL" : "\"\(name)\" = \(quoted)"
        // Przez komendę filtra wyrażeniem (R4-18) — ta sama walidacja, dziennik komend i makra.
        workspace.perform("grid.filterExpression", CommandArguments(["expression": .string(expr)]))
    }
}

/// Biblioteka snippetów (SC-SNIP-001): filtr, kategorie, dwuklik wstawia, przeciągnięcie do edytora, własne fragmenty.
struct SnippetsView: View {
    let workspace: Workspace
    @State private var filter = ""
    @State private var selection: Snippet.ID?
    @State private var snippets: [Snippet] = []
    @State private var editing: Snippet?
    @State private var message = ""

    private var visible: [Snippet] {
        filter.isEmpty ? snippets : snippets.filter { $0.name.localizedCaseInsensitiveContains(filter) || $0.text.localizedCaseInsensitiveContains(filter) || $0.category.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField(L10n.tr("Szukaj"), text: $filter).textFieldStyle(.roundedBorder)
                Button { editing = Snippet(category: L10n.tr("Moje"), name: L10n.tr("Nowy"), text: "") } label: { Image(systemName: "plus") }
                    .iconLabel(L10n.tr("Nowy fragment kodu"))
            }
            List(selection: $selection) {
                ForEach(Array(Set(visible.map(\.category))).sorted(), id: \.self) { cat in
                    Section(cat) {
                        ForEach(visible.filter { $0.category == cat }) { s in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.name)
                                Text(s.text.components(separatedBy: "\n").first ?? "").font(.code).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .tag(s.id)
                            .draggable(s.text)
                        }
                    }
                }
            }
            .contextMenu(forSelectionType: Snippet.ID.self) { ids in
                if let id = ids.first, let s = snippets.first(where: { $0.id == id }) {
                    Button(L10n.tr("Wstaw")) { insert(s) }
                    Button(L10n.tr("Edytuj…")) { editing = s }
                    if !s.isBuiltIn {
                        Button(L10n.tr("Usuń")) { run("snippets.remove", ["id": .string(s.id)]) }
                    }
                }
            } primaryAction: { ids in
                if let id = ids.first, let s = snippets.first(where: { $0.id == id }) { insert(s) }
            }
            Text(message.isEmpty ? L10n.tr("Dwukrotne kliknięcie wstawia w miejscu kursora; fragment można też przeciągnąć do edytora.") : message)
                .font(.uiSecondary).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(minWidth: 380, minHeight: 420)
        .onAppear { reload() }
        .sheet(item: $editing) { s in
            SnippetEditor(snippet: s) { edited in
                editing = nil
                guard let edited else { return }
                // Edycja własnego snippetu ze zmianą nazwy zastępuje go (wbudowany zostaje — własny go przesłania).
                var args: [String: JSONValue] = ["category": .string(edited.category), "name": .string(edited.name), "text": .string(edited.text)]
                if snippets.contains(where: { $0.id == s.id && !$0.isBuiltIn }) { args["replaces"] = .string(s.id) }
                run("snippets.save", args)
            }
        }
    }

    private func reload() { snippets = workspace.snippets.all }

    /// Zapis i usunięcie przez komendy rejestru (dziennik komend, makra; usunięcie z potwierdzeniem).
    private func run(_ id: CommandID, _ arguments: [String: JSONValue]) {
        Task {
            do { try await workspace.invoke(id, CommandArguments(arguments)); message = "" } catch CommandError.cancelledByUser {
            } catch { message = error.localizedDescription }
            reload()
        }
    }

    private func insert(_ s: Snippet) {
        Task {
            do { try await workspace.invoke("edit.insertSnippet", CommandArguments(["id": .string(s.id)])); message = "" }
            catch { message = error.localizedDescription }
        }
    }
}

struct SnippetEditor: View {
    @State var snippet: Snippet
    let done: (Snippet?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L10n.tr("Kategoria"), text: $snippet.category)
            TextField(L10n.tr("Nazwa"), text: $snippet.name)
            CodeTextEditor(text: $snippet.text).frame(minHeight: 160)
            HStack {
                Spacer()
                Button(L10n.tr("Anuluj"), role: .cancel) { done(nil) }.keyboardShortcut(.cancelAction)
                Button(L10n.tr("Zapisz")) { done(snippet) }.disabled(snippet.name.isEmpty || snippet.category.isEmpty)
            }
        }
        .padding(14)
        .frame(minWidth: 480, idealWidth: 480, maxWidth: .infinity)
    }
}
