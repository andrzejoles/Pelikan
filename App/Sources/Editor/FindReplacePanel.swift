import AppKit
import PelikanWorkspace
import SwiftUI

/// Znajdź i zamień (UG 25.3) — panel pływający działający na aktywnym edytorze przez model (`TextSearch`).
@MainActor
@Observable
final class FindReplaceModel {
    var search = TextSearch(pattern: "")
    var inSelection = false
    var message: String?
    let workspace: Workspace

    init(workspace: Workspace) {
        self.workspace = workspace
        if let last = workspace.lastSearch { search = last }
    }

    var document: PelikanWorkspace.Document? {
        guard let d = workspace.activeDocument, [.sql, .command, .program, .test].contains(d.kind) else { return nil }
        return d
    }

    func find(backwards: Bool = false) {
        guard !search.pattern.isEmpty else { return }
        workspace.lastSearch = search
        message = nil
        guard let doc = document else { return }
        do {
            let from = backwards ? doc.selectedRange.lowerBound : doc.selectedRange.upperBound
            if let r = try search.next(in: doc.text, from: from, backwards: backwards) {
                doc.selectedRange = r
            } else {
                message = L10n.tr("Nie znaleziono")
            }
        } catch {
            message = L10n.tr("Błędne wyrażenie regularne: \(error.localizedDescription)")
        }
    }

    /// Zamiana przez komendy rejestru (`edit.replace`, `edit.replaceAll`): tylko do odczytu, trwające wykonanie, okno
    /// poleceń dla agenta i cofanie — jak w innych komendach edycji (R4-06).
    func replace() { invokeReplace("edit.replace") }

    func replaceAll() { invokeReplace("edit.replaceAll", ["inSelection": .bool(inSelection)]) }

    private func invokeReplace(_ id: CommandID, _ args: [String: JSONValue] = [:]) {
        guard document != nil, !search.pattern.isEmpty else { return }
        workspace.lastSearch = search
        message = nil
        Task {
            do {
                message = try await workspace.invoke(id, CommandArguments(args)).message
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

struct FindReplaceView: View {
    @Bindable var model: FindReplaceModel

    var body: some View {
        Form {
            TextField(L10n.tr("Szukaj"), text: $model.search.pattern).onSubmit { model.find() }
            TextField(L10n.tr("Zamień na"), text: $model.search.replacement)
            HStack {
                Toggle(L10n.tr("Wyrażenie regularne"), isOn: $model.search.regex)
                Toggle(L10n.tr("Całe słowa"), isOn: $model.search.wholeWords)
                Toggle(L10n.tr("Wielkość liter"), isOn: $model.search.caseSensitive)
            }
            HStack {
                Toggle(L10n.tr("Zachowaj wielkość liter"), isOn: $model.search.preserveCase)
                Toggle(L10n.tr("Tylko w zaznaczeniu"), isOn: $model.inSelection)
            }
            HStack {
                Text(L10n.tr("Szukaj w:"))
                Toggle(L10n.tr("kodzie"), isOn: $model.search.inCode)
                Toggle(L10n.tr("komentarzach"), isOn: $model.search.inComments)
                Toggle(L10n.tr("literałach"), isOn: $model.search.inStrings)
            }
            HStack {
                if let m = model.message { Text(m).font(.uiSecondary).foregroundStyle(.secondary) }
                Spacer()
                Button(L10n.tr("Poprzednie")) { model.find(backwards: true) }
                Button(L10n.tr("Zamień")) { model.replace() }
                Button(L10n.tr("Zamień wszystko")) { model.replaceAll() }
                Button(L10n.tr("Następne")) { model.find() }.keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .windowSize(width: 600, height: 330)
    }
}

/// Historia poleceń (Recall Statement, UG 25.5): filtr, podgląd, wstawienie do edytora (zamiast zaznaczenia).
struct RecallStatementView: View {
    let workspace: Workspace
    let onClose: () -> Void
    @State private var filter = ""
    @State private var selection: Set<Int> = []

    var entries: [(Int, HistoryEntry)] {
        Array(workspace.history.enumerated()).filter { filter.isEmpty || $0.element.text.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L10n.tr("Filtr"), text: $filter)
            List(entries, id: \.0, selection: $selection) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.1.text.replacingOccurrences(of: "\n", with: " ")).font(.body.monospaced()).lineLimit(2)
                    Text("\(item.1.date.formatted(date: .abbreviated, time: .shortened))  ·  \(item.1.user)").font(.uiSecondary).foregroundStyle(.secondary)
                }
                .contextMenu { Button(L10n.tr("Wstaw")) { insert([item.0]) } }
            }
            .onKeyPress(.return) { insert(Array(selection)); return .handled }
            HStack {
                Text(L10n.tr("Wpisów: \(entries.count)")).font(.uiSecondary).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.tr("Zamknij"), action: onClose).keyboardShortcut(.cancelAction)
                Button(L10n.tr("Wstaw")) { insert(Array(selection)) }.keyboardShortcut(.defaultAction).disabled(selection.isEmpty)
            }
        }
        .padding(14)
        .windowSize(width: 640, height: 460)
    }

    /// Wiele zaznaczonych poleceń — rozdzielone pustą linią, każde zakończone średnikiem (jak „wiele naraz” we wzorcu).
    func insert(_ indexes: [Int]) {
        guard let doc = workspace.activeDocument, [.sql, .command, .program, .test].contains(doc.kind), !indexes.isEmpty else { return }
        // Jak komendy edycji: okno tylko do odczytu i okno w trakcie wykonania nie przyjmują tekstu (R4-06).
        if doc.isReadOnly || doc.isExecuting {
            workspace.ui?.showError(doc.isReadOnly ? L10n.tr("Okno jest tylko do odczytu") : L10n.tr("Okno już wykonuje polecenie"))
            return
        }
        let texts = indexes.sorted().compactMap { workspace.history.indices.contains($0) ? workspace.history[$0].text : nil }
        let block = texts.count == 1 ? texts[0] : texts.map { $0.hasSuffix(";") || $0.hasSuffix("/") ? $0 : $0 + ";" }.joined(separator: "\n\n")
        let ns = doc.text as NSString
        let sel = NSRange(location: min(doc.selectedRange.lowerBound, ns.length), length: min(doc.selectedRange.count, ns.length - min(doc.selectedRange.lowerBound, ns.length)))
        doc.text = ns.replacingCharacters(in: sel, with: block)
        doc.selectedRange = sel.location..<(sel.location + (block as NSString).length)
        onClose()
    }
}
