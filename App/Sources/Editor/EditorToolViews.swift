import AppKit
import PelikanWorkspace
import SwiftUI

/// Biblioteka makr (PD-EDIT-015): odtwarzanie, nazwa, skrót klawiszowy, usuwanie; zapis bieżącego nagrania.
struct MacroLibraryView: View {
    let workspace: Workspace
    @State private var selection: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(workspace.isRecordingMacro ? L10n.tr("Trwa nagrywanie (F11 kończy)") : workspace.currentMacro.map { L10n.tr("Bieżące makro: \($0.steps.count) kroków") } ?? L10n.tr("Brak nagrania"))
                    .font(.ui).foregroundStyle(workspace.isRecordingMacro ? .red : .secondary)
                Spacer()
                Button(L10n.tr("Zapisz bieżące…")) { workspace.perform("edit.macroSave") }.disabled(workspace.currentMacro == nil)
            }
            Table(workspace.macroLibrary.macros, selection: $selection) {
                TableColumn(L10n.tr("Nazwa")) { m in
                    TextField("", text: binding(m, \.name)).textFieldStyle(.plain)
                }
                TableColumn(L10n.tr("Skrót")) { m in
                    TextField(L10n.tr("np. ctrl+shift+1"), text: Binding(get: { m.key ?? "" }, set: { value in
                        var lib = workspace.macroLibrary
                        guard let i = lib.macros.firstIndex(where: { $0.id == m.id }) else { return }
                        lib.macros[i].key = value.isEmpty ? nil : value
                        workspace.updateMacros(lib)
                    })).textFieldStyle(.plain)
                }.width(140)
                TableColumn(L10n.tr("Kroki")) { m in Text("\(m.steps.count)").monospacedDigit() }.width(50)
            }
            .contextMenu(forSelectionType: UUID.self) { _ in } primaryAction: { ids in
                if let id = ids.first, let m = workspace.macroLibrary.macros.first(where: { $0.id == id }) { play(m) }
            }
            HStack {
                Button(L10n.tr("Odtwórz")) { if let m = selected { play(m) } }.disabled(selected == nil)
                Button(L10n.tr("Usuń")) {
                    var lib = workspace.macroLibrary
                    lib.macros.removeAll { $0.id == selection }
                    workspace.updateMacros(lib)
                }.disabled(selected == nil)
                Spacer()
                Text(L10n.tr("Skrót zajęty przez inną komendę jest pomijany.")).font(.uiSecondary).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(minWidth: 420, minHeight: 300)
    }

    private var selected: Macro? { workspace.macroLibrary.macros.first { $0.id == selection } }

    private func play(_ m: Macro) {
        NSApp.mainWindow?.makeKeyAndOrderFront(nil)
        workspace.perform(m.commandID)
    }

    private func binding(_ m: Macro, _ path: WritableKeyPath<Macro, String>) -> Binding<String> {
        Binding(get: { m[keyPath: path] }, set: { value in
            var lib = workspace.macroLibrary
            guard let i = lib.macros.firstIndex(where: { $0.id == m.id }) else { return }
            lib.macros[i][keyPath: path] = value
            workspace.updateMacros(lib)
        })
    }
}

/// Historia schowka (PD-EDIT-024): filtr, podgląd, dwuklik wkleja do aktywnego edytora.
struct ClipboardHistoryView: View {
    let workspace: Workspace
    @State private var filter = ""
    @State private var selection: UUID?

    var body: some View {
        let entries = workspace.clipboardHistory.filtered(filter)
        VStack(alignment: .leading, spacing: 8) {
            TextField(L10n.tr("Filtr"), text: $filter).textFieldStyle(.roundedBorder)
            VSplitView {
                List(entries, selection: $selection) { e in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(e.title).lineLimit(1).font(.code)
                        Text(e.date.formatted(date: .omitted, time: .standard)).font(.uiSecondary).foregroundStyle(.secondary)
                    }
                    .tag(e.id)
                }
                .contextMenu(forSelectionType: UUID.self) { _ in } primaryAction: { ids in
                    if let id = ids.first { paste(id, in: entries) }
                }
                .frame(minHeight: 160)
                ScrollView {
                    Text(entries.first { $0.id == selection }?.text ?? "")
                        .font(.code).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading).padding(6)
                }
                .frame(minHeight: 100)
            }
            HStack {
                Button(L10n.tr("Wklej")) { if let id = selection { paste(id, in: entries) } }.disabled(selection == nil)
                Spacer()
                Text(L10n.tr("Historia tylko w pamięci — znika po zamknięciu Pelikana.")).font(.uiSecondary).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(minWidth: 400, minHeight: 360)
    }

    private func paste(_ id: UUID, in entries: [ClipboardEntry]) {
        guard let i = workspace.clipboardHistory.entries.firstIndex(where: { $0.id == id }) else { return }
        NSApp.mainWindow?.makeKeyAndOrderFront(nil)
        workspace.perform("edit.pasteFromHistory", CommandArguments(["index": .int(Int64(i))]))
    }
}

/// Zadania To-Do z komentarzy otwartych okien (PD-TODO-001): dwuklik przechodzi do linii, przełączanie zamknięcia.
struct TodoItemsView: View {
    let workspace: Workspace
    @State private var showClosed = false
    @State private var selection: String?
    @State private var cache = Cache()

    struct Row: Identifiable {
        let document: PelikanWorkspace.Document
        let item: TodoItem
        var id: String { "\(document.id.raw.uuidString):\(item.id)" }
    }

    /// Zadania okna liczone ponownie tylko po zmianie jego tekstu — widok przelicza się przy zmianie dowolnego okna.
    @MainActor final class Cache {
        private var entries: [DocumentID: (text: String, items: [TodoItem])] = [:]

        func items(_ d: PelikanWorkspace.Document) -> [TodoItem] {
            if let e = entries[d.id], e.text == d.text { return e.items }
            let items = TodoItems.parse(d.text)
            entries[d.id] = (d.text, items)
            return items
        }

        func keep(_ ids: Set<DocumentID>) { entries = entries.filter { ids.contains($0.key) } }
    }

    private var rows: [Row] {
        cache.keep(Set(workspace.documents.map(\.id)))
        return workspace.documents.flatMap { d in cache.items(d).map { Row(document: d, item: $0) } }
            .filter { showClosed || !$0.item.closed }
            .sorted { ($0.item.priority ?? Int.max, $0.document.title, $0.item.line) < ($1.item.priority ?? Int.max, $1.document.title, $1.item.line) }
    }

    var body: some View {
        let rows = rows
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(L10n.tr("Pokaż zamknięte"), isOn: $showClosed).toggleStyle(.checkbox)
                Spacer()
                Text(L10n.tr("Składnia: -- TODO(właściciel) !priorytet #kategoria: tekst")).font(.uiSecondary).foregroundStyle(.secondary)
            }
            Table(rows, selection: $selection) {
                TableColumn("") { r in Image(systemName: r.item.closed ? "checkmark.circle.fill" : "circle").foregroundStyle(r.item.closed ? .green : .secondary) }.width(22)
                TableColumn(L10n.tr("Zadanie")) { r in Text(r.item.text).strikethrough(r.item.closed) }
                TableColumn(L10n.tr("Priorytet")) { r in Text(r.item.priority.map(String.init) ?? "") }.width(60)
                TableColumn(L10n.tr("Kategoria")) { r in Text(r.item.category ?? "") }.width(90)
                TableColumn(L10n.tr("Właściciel")) { r in Text(r.item.owner ?? "") }.width(90)
                TableColumn(L10n.tr("Okno")) { r in Text("\(r.document.title):\(r.item.line)").foregroundStyle(.secondary) }.width(120)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                Button(L10n.tr("Zamknij / otwórz")) { if let id = ids.first, let r = rows.first(where: { $0.id == id }) { toggle(r) } }
            } primaryAction: { ids in
                if let id = ids.first, let r = rows.first(where: { $0.id == id }) { go(r) }
            }
        }
        .padding(10)
        .frame(minWidth: 520, minHeight: 300)
    }

    private func go(_ r: Row) {
        workspace.activate(r.document.id)
        let p = r.item.keywordRange.lowerBound
        r.document.selectedRange = p..<p
        NSApp.mainWindow?.makeKeyAndOrderFront(nil)
    }

    /// Przez komendę `edit.todoToggle` w oknie zadania — tylko do odczytu i trwające wykonanie jak w menu (R4-06).
    private func toggle(_ r: Row) {
        workspace.activate(r.document.id)
        workspace.perform("edit.todoToggle", CommandArguments(["line": .int(Int64(r.item.line))]))
    }
}
