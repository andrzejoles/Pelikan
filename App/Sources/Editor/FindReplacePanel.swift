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

    func replace() {
        guard let doc = document, !search.pattern.isEmpty else { return }
        workspace.lastSearch = search
        do {
            if let r = try search.replace(in: doc.text, selection: doc.selectedRange) {
                doc.text = r.text
                doc.selectedRange = r.range.upperBound..<r.range.upperBound
            }
            find()
        } catch {
            message = L10n.tr("Błędne wyrażenie regularne: \(error.localizedDescription)")
        }
    }

    func replaceAll() {
        guard let doc = document, !search.pattern.isEmpty else { return }
        workspace.lastSearch = search
        do {
            let scope = inSelection && !doc.selectedRange.isEmpty ? doc.selectedRange : nil
            let r = try search.replaceAll(in: doc.text, within: scope)
            if r.count > 0 { doc.text = r.text }
            message = L10n.tr("Zamieniono: \(r.count)")
        } catch {
            message = L10n.tr("Błędne wyrażenie regularne: \(error.localizedDescription)")
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
                if let m = model.message { Text(m).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button(L10n.tr("Poprzednie")) { model.find(backwards: true) }
                Button(L10n.tr("Zamień")) { model.replace() }
                Button(L10n.tr("Zamień wszystko")) { model.replaceAll() }
                Button(L10n.tr("Następne")) { model.find() }.keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .frame(width: 600, height: 330)
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
                    Text("\(item.1.date.formatted(date: .abbreviated, time: .shortened))  ·  \(item.1.user)").font(.caption).foregroundStyle(.secondary)
                }
                .contextMenu { Button(L10n.tr("Wstaw")) { insert([item.0]) } }
            }
            .onKeyPress(.return) { insert(Array(selection)); return .handled }
            HStack {
                Text(L10n.tr("Wpisów: \(entries.count)")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.tr("Zamknij"), action: onClose).keyboardShortcut(.cancelAction)
                Button(L10n.tr("Wstaw")) { insert(Array(selection)) }.keyboardShortcut(.defaultAction).disabled(selection.isEmpty)
            }
        }
        .padding(14)
        .frame(width: 640, height: 460)
    }

    /// Wiele zaznaczonych poleceń — rozdzielone pustą linią, każde zakończone średnikiem (jak „wiele naraz” we wzorcu).
    func insert(_ indexes: [Int]) {
        guard let doc = workspace.activeDocument, !indexes.isEmpty else { return }
        let texts = indexes.sorted().compactMap { workspace.history.indices.contains($0) ? workspace.history[$0].text : nil }
        let block = texts.count == 1 ? texts[0] : texts.map { $0.hasSuffix(";") || $0.hasSuffix("/") ? $0 : $0 + ";" }.joined(separator: "\n\n")
        let ns = doc.text as NSString
        let sel = NSRange(location: min(doc.selectedRange.lowerBound, ns.length), length: min(doc.selectedRange.count, ns.length - min(doc.selectedRange.lowerBound, ns.length)))
        doc.text = ns.replacingCharacters(in: sel, with: block)
        doc.selectedRange = sel.location..<(sel.location + (block as NSString).length)
        onClose()
    }
}
