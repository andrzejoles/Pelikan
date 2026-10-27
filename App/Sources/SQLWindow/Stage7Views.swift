import AppKit
import PelikanDB
import PelikanWorkspace
import SwiftUI
import WebKit

/// Panel wartości obok siatki (DB-PANEL-001): bieżąca komórka jako tekst, JSON, XML, HTML, obraz albo hex.
struct CellValuePanelView: View {
    @Bindable var tab: ResultTab
    let grid: ResultGridModel
    @State private var mode: CellValuePresentation.Mode?

    private var presentation: CellValuePresentation? {
        guard let row = tab.selectedRows?.first, let col = tab.currentColumn, row < grid.rowCount, col < grid.columns.count else { return nil }
        return CellValuePresentation.make(grid.value(row: row, column: col), column: grid.columns[col], format: grid.format)
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
                if p.truncated { Text(L10n.tr("Wartość obcięta do pobranej długości — pełna w Large Data Editor")).font(.uiSecondary).foregroundStyle(.orange) }
                content(p, mode.flatMap { p.modes.contains($0) ? $0 : nil } ?? p.detected)
            } else {
                Text(L10n.tr("Zaznacz komórkę")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(6)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func label(_ m: CellValuePresentation.Mode) -> String {
        switch m {
        case .text: L10n.tr("Tekst")
        case .json: "JSON"
        case .xml: "XML"
        case .html: "HTML"
        case .image: L10n.tr("Obraz")
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
        default:
            ScrollView([.vertical, .horizontal]) {
                Text(p.rendered(m)).font(.code).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
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
            Table(counts, selection: $selection) {
                TableColumn(L10n.tr("Wartość")) { g in Text(g.value).foregroundStyle(g.isNull ? .secondary : .primary) }
                TableColumn(L10n.tr("Liczba")) { g in Text("\(g.count)").monospacedDigit() }.width(70)
            }
            .contextMenu(forSelectionType: GroupCount.ID.self) { _ in } primaryAction: { ids in
                if let id = ids.first, let g = counts.first(where: { $0.id == id }) { apply(g) }
            }
            Text(L10n.tr("Dwuklik — pokaż w siatce tylko wiersze z tą wartością.")).font(.uiSecondary).foregroundStyle(.secondary)
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
                    .iconLabel(L10n.tr("Nowy snippet"))
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
            Text(message.isEmpty ? L10n.tr("Dwuklik wstawia w miejscu kursora; fragment można też przeciągnąć do edytora.") : message)
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
