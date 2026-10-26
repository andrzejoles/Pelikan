import AppKit
import PelikanDB
import PelikanWorkspace
import SwiftUI

/// Wyniki Find Usages (DG-USE-001): baza (zależności, źródło, PL/Scope), okna i pliki; dwuklik przechodzi do miejsca.
struct UsagesView: View {
    let workspace: Workspace
    let title: String
    let hits: [UsageHit]
    /// Stopka zamiast „Użycia …: n” (np. wyniki paska wyszukiwania).
    var summary: String? = nil
    @State private var selection: UsageHit.ID?

    static func kindText(_ k: UsageHit.Kind) -> String {
        switch k {
        case .dependency: L10n.tr("zależność")
        case .source: L10n.tr("kod w bazie")
        case .plscope: "PL/Scope"
        case .document: L10n.tr("okno")
        case .file: L10n.tr("plik")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Table(hits, selection: $selection) {
                TableColumn(L10n.tr("Rodzaj")) { (h: UsageHit) in Text(Self.kindText(h.kind)) }.width(min: 70, ideal: 90)
                TableColumn(L10n.tr("Miejsce")) { (h: UsageHit) in Text(h.title + (h.type.map { " (\($0.lowercased()))" } ?? "")) }.width(min: 140, ideal: 220)
                TableColumn(L10n.tr("Linia")) { (h: UsageHit) in Text(h.line > 0 ? String(h.line) : "") }.width(min: 40, ideal: 50)
                TableColumn(L10n.tr("Tekst")) { (h: UsageHit) in Text(h.text).font(.system(size: 12, design: .monospaced)).lineLimit(1) }
            }
            .contextMenu(forSelectionType: UsageHit.ID.self) { _ in } primaryAction: { ids in
                if let id = ids.first, let h = hits.first(where: { $0.id == id }) { open(h) }
            }
            Text(summary ?? (hits.isEmpty ? L10n.tr("Brak użyć \(title)") : L10n.tr("Użycia \(title): \(hits.count)")))
                .foregroundStyle(.secondary).font(.ui)
        }
        .padding(12)
        .frame(minWidth: 620, minHeight: 320)
    }

    private func open(_ h: UsageHit) {
        switch h.kind {
        case .document:
            guard let id = h.document, let d = workspace.documents.first(where: { $0.id == id }) else { return }
            workspace.activeDocumentID = id
            let o = ProgramCompiler.offset(line: h.line, column: 1, in: d.text)
            d.selectedRange = o..<o
        case .file:
            guard let u = h.fileURL, let d = try? workspace.openFile(u) else { return }
            let o = ProgramCompiler.offset(line: h.line, column: 1, in: d.text)
            d.selectedRange = o..<o
        case .dependency, .source, .plscope:
            guard let owner = h.owner, let name = h.name, let type = h.type.flatMap(DBObjectType.init(rawValue:)) else { return }
            Task { try? await workspace.openObject(DBObject(owner: owner, name: name, type: type), line: h.line) }
        }
        NSApp.mainWindow?.makeKeyAndOrderFront(nil)
    }
}

/// Podgląd refaktoryzacji (DG-REF-001): lista zmienionych tekstów, różnice wybranego, DDL do okna SQL; Zastosuj/Anuluj.
struct RefactoringPreviewView: View {
    let plan: RefactoringPlan
    let finish: (Bool) -> Void
    @State private var selection: RefactoringChange.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(plan.title).font(.uiHeadline)
            HSplitView {
                List(plan.changes, selection: $selection) { c in
                    VStack(alignment: .leading) {
                        Text(c.title)
                        Text(L10n.tr("zmian: \(c.occurrences)")).font(.uiSecondary).foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 180, idealWidth: 220)
                Group {
                    if let c = plan.changes.first(where: { $0.id == (selection ?? plan.changes.first?.id) }) {
                        DiffViewer(left: c.before, right: c.after, leftTitle: L10n.tr("Przed"), rightTitle: L10n.tr("Po"))
                            .id(c.id)
                    } else {
                        Text(L10n.tr("Brak zmian w tekstach")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 420)
            }
            if let ddl = plan.ddl {
                Text(L10n.tr("DDL zmiany w bazie (nowe okno SQL, bez wykonania):")).font(.ui)
                Text(ddl).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
            }
            HStack {
                Spacer()
                Button(L10n.tr("Anuluj")) { finish(false) }.keyboardShortcut(.cancelAction)
                Button(L10n.tr("Zastosuj")) { finish(true) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(minWidth: 860, minHeight: 520)
    }
}

/// Historia lokalna okna (DG-HIST-001): wersje od najnowszej, podgląd, porównanie z bieżącym tekstem, przywrócenie.
struct LocalHistoryView: View {
    let workspace: Workspace
    let document: PelikanWorkspace.Document
    @State private var selection: LocalHistoryEntry.ID?

    private var entries: [LocalHistoryEntry] {
        _ = workspace.localHistory.revision
        guard let (key, _) = workspace.historyKey(for: document) else { return [] }
        return workspace.localHistory.entries(key)
    }

    var body: some View {
        let list = entries
        VStack(alignment: .leading, spacing: 8) {
            HSplitView {
                Table(list, selection: $selection) {
                    TableColumn(L10n.tr("Czas")) { (e: LocalHistoryEntry) in Text(e.date, format: .dateTime.year().month().day().hour().minute().second()) }
                        .width(min: 130, ideal: 150)
                    TableColumn(L10n.tr("Zdarzenie")) { (e: LocalHistoryEntry) in Text(e.label) }.width(min: 80, ideal: 120)
                }
                .contextMenu(forSelectionType: LocalHistoryEntry.ID.self) { _ in } primaryAction: { ids in
                    if let id = ids.first { run("file.localHistoryCompare", id) }
                }
                .frame(minWidth: 260)
                Group {
                    if let e = list.first(where: { $0.id == selection }) {
                        ScrollView {
                            Text(e.text)
                                .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(6)
                        }
                    } else {
                        Text(list.isEmpty ? L10n.tr("Brak zapisanych wersji") : L10n.tr("Wybierz wersję, aby zobaczyć jej tekst"))
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 320)
            }
            // Najnowsza wersja wybrana od razu — podgląd zamiast pustego panelu.
            .onAppear { if selection == nil { selection = list.first?.id } }
            HStack {
                Text(L10n.tr("Wersji: \(list.count)")).foregroundStyle(.secondary).font(.ui)
                Spacer()
                Button(L10n.tr("Porównaj z bieżącym")) { if let s = selection { run("file.localHistoryCompare", s) } }.disabled(selection == nil)
                Button(L10n.tr("Przywróć")) { if let s = selection { run("file.localHistoryRestore", s) } }.disabled(selection == nil)
            }
        }
        .padding(12)
        .frame(minWidth: 640, minHeight: 360)
    }

    private func run(_ id: CommandID, _ entry: UUID) {
        workspace.activeDocumentID = document.id
        workspace.perform(id, CommandArguments(["entry": .string(entry.uuidString)]))
    }
}

/// Lista problemów analizy kodu okna (DG-RES-001, DG-INSP-001); wybór zaznacza miejsce w tekście.
struct ProblemsView: View {
    let workspace: Workspace
    let document: PelikanWorkspace.Document
    @State private var selection: EditorDiagnostic.ID?

    var body: some View {
        let list = workspace.diagnostics[document.id] ?? []
        VStack(alignment: .leading, spacing: 8) {
            Table(list, selection: $selection) {
                TableColumn("") { (d: EditorDiagnostic) in
                    Image(systemName: d.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(d.severity == .error ? .red : .orange)
                }.width(20)
                TableColumn(L10n.tr("Linia")) { (d: EditorDiagnostic) in Text(String(d.line(in: document.text))) }.width(min: 40, ideal: 50)
                TableColumn(L10n.tr("Problem")) { (d: EditorDiagnostic) in Text(d.message) }
            }
            .onChange(of: selection) { _, id in
                guard let d = list.first(where: { $0.id == id }) else { return }
                workspace.activeDocumentID = document.id
                document.selectedRange = d.range
            }
            HStack {
                Text(L10n.tr("Problemów: \(list.count)")).foregroundStyle(.secondary).font(.ui)
                Spacer()
                Button(L10n.tr("Analizuj ponownie")) { Task { await workspace.analyzeCode(document) } }
            }
        }
        .padding(12)
        .frame(minWidth: 520, minHeight: 260)
    }
}
