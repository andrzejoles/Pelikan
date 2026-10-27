import AppKit
import PelikanDB
import PelikanWorkspace
import SwiftUI

/// Okno wyników utPLSQL (PROMPT §6): postęp na żywo, liczniki, filtr statusów, drzewo suit i testów z czasami,
/// szczegóły testu (oczekiwania, stos błędu z przejściem do linii, DBMS_OUTPUT), ponowne uruchomienie, pokrycie.
struct UtplsqlResultsView: View {
    let workspace: Workspace
    @Bindable var run: UtplsqlRun
    @State private var selection: String?
    @State private var shown: Set<UtStatus> = Set(UtStatus.allCases)
    @State private var showChanges = false
    @State private var sortOrder: UtSortOrder = .execution

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            HSplitView {
                tree.frame(minWidth: 320)
                details.frame(minWidth: 280)
            }
        }
        .padding(10)
        .frame(minWidth: 760, minHeight: 440)
        .sheet(isPresented: $showChanges) { changes }
    }

    /// Poprzedni przebieg w historii (porównanie, UT-RES-003).
    private var previous: UtplsqlRun? {
        guard let i = workspace.utplsqlHistory.firstIndex(where: { $0.id == run.id }), i + 1 < workspace.utplsqlHistory.count else { return nil }
        return workspace.utplsqlHistory[i + 1]
    }

    private var changes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("Zmiany względem poprzedniego przebiegu")).font(.uiHeadline)
            let diff = previous.map { run.compare(with: $0) } ?? []
            if diff.isEmpty { Text(L10n.tr("Bez zmian stanów testów.")).foregroundStyle(.secondary) }
            List(diff, id: \.path) { d in
                HStack {
                    Text(d.path).font(.code).lineLimit(1).truncationMode(.head)
                    Spacer()
                    Text(d.before?.displayName ?? L10n.tr("nowy")).foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                    Text(d.after.displayName).foregroundStyle(UtNodeRow.color(d.after))
                }
            }
            HStack { Spacer(); Button(L10n.tr("Zamknij")) { showChanges = false }.keyboardShortcut(.defaultAction) }
        }
        .padding(14)
        .frame(minWidth: 560, minHeight: 300)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(run.paths.joined(separator: ", ")).font(.uiHeadline).lineLimit(1)
                Spacer()
                if !run.finished {
                    Button(L10n.tr("Przerwij")) { workspace.perform("utplsql.cancel") }
                } else {
                    Button(L10n.tr("Uruchom ponownie")) { workspace.perform("utplsql.runPath", CommandArguments(["path": .string(run.paths.joined(separator: ","))])) }
                    Button(L10n.tr("Ponownie nieudane")) { workspace.perform("utplsql.rerunFailed") }.disabled(run.failedPaths.isEmpty)
                    if run.coverageHTML != nil { Button(L10n.tr("Raport pokrycia")) { openCoverage() } }
                    Menu(L10n.tr("Historia")) {
                        ForEach(workspace.utplsqlHistory) { r in
                            Button("\(r.started.formatted(date: .omitted, time: .standard)) — \(r.paths.joined(separator: ", ")) (\(r.counter.success)/\(r.counter.total))") {
                                workspace.ui?.showUtplsqlResults(r)
                            }
                        }
                    }
                    Button(L10n.tr("Zmiany")) { showChanges = true }.disabled(previous == nil)
                }
            }
            if let f = run.failure {
                Text(f).foregroundStyle(.red).font(.ui)
            }
            ProgressView(value: Double(run.finishedTests), total: Double(max(run.totalTests, 1)))
            HStack(spacing: 14) {
                counter(L10n.tr("Testy"), "\(run.finishedTests)/\(run.totalTests)", .primary)
                counter(L10n.tr("Sukces"), "\(tests(.success))", .green)
                counter(L10n.tr("Niepowodzenia"), "\(tests(.failure))", .orange)
                counter(L10n.tr("Błędy"), "\(tests(.error))", .red)
                counter(L10n.tr("Wyłączone"), "\(tests(.disabled))", .secondary)
                if let t = run.executionTime { counter(L10n.tr("Czas"), String(format: "%.3f s", t), .secondary) }
                Spacer()
                if let c = run.currentTest { Text(c).font(.uiSecondary).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head) }
            }
            HStack(spacing: 10) {
                Text(L10n.tr("Pokaż:")).font(.uiSecondary)
                ForEach([UtStatus.success, .failure, .error, .disabled], id: \.self) { s in
                    Toggle(s.displayName, isOn: Binding(get: { shown.contains(s) }, set: { if $0 { shown.insert(s) } else { shown.remove(s) } }))
                        .toggleStyle(.checkbox).font(.uiSecondary)
                }
                Spacer()
                Picker(L10n.tr("Sortuj:"), selection: $sortOrder) {
                    ForEach(UtSortOrder.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .font(.uiSecondary)
                .fixedSize()
            }
        }
    }

    private func tests(_ s: UtStatus) -> Int { run.tests.filter { $0.status == s }.count }

    private func counter(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.uiSecondary).foregroundStyle(.secondary)
            Text(value).font(.system(.body, design: .rounded).bold()).foregroundStyle(color)
        }
    }

    /// Drzewo z filtrem statusów (suity bez pasujących testów są ukrywane).
    private var filteredRoots: [UtNode] {
        func filter(_ n: UtNode) -> UtNode? {
            if n.kind == .test { return shown.contains(n.status) || [.pending, .running].contains(n.status) ? n : nil }
            var c = n
            c.children = (n.children ?? []).compactMap(filter)
            return c.children?.isEmpty == false ? c : nil
        }
        return sortOrder.sorted(run.roots.compactMap(filter))
    }

    private var tree: some View {
        List(selection: $selection) {
            ForEach(filteredRoots) { n in UtNodeRow(node: n, workspace: workspace, open: { openSource($0, line: 0) }) }
        }
    }

    private var selected: UtNode? {
        guard let id = selection else { return nil }
        func find(_ n: [UtNode]) -> UtNode? {
            for x in n { if x.id == id { return x }; if let f = find(x.children ?? []) { return f } }
            return nil
        }
        return find(run.roots)
    }

    /// Otrzymane i oczekiwane obok siebie; linie różniące się wyróżnione (UT-RES-002).
    private func comparison(_ c: (actual: String, expected: String)) -> some View {
        let a = c.actual.components(separatedBy: "\n"), e = c.expected.components(separatedBy: "\n")
        func column(_ title: String, _ lines: [String], _ other: [String]) -> some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.uiSecondary.bold()).foregroundStyle(.secondary)
                ForEach(Array(lines.enumerated()), id: \.offset) { i, l in
                    Text(l).font(.code).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(i < other.count && other[i] == l ? Color.clear : Color.red.opacity(0.12))
                }
            }
        }
        return HStack(alignment: .top, spacing: 8) {
            column(L10n.tr("Otrzymane"), a, e)
            Divider()
            column(L10n.tr("Oczekiwane"), e, a)
        }
        .padding(6)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
    }

    private var details: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let n = selected {
                    Text(n.title).font(.uiHeadline)
                    Text(n.id).font(.code).foregroundStyle(.secondary).textSelection(.enabled)
                    Text(n.status.displayName).foregroundStyle(color(n.status))
                    if !n.disabledReason.isEmpty { Text(L10n.tr("Wyłączony: \(n.disabledReason)")).foregroundStyle(.secondary) }
                    ForEach(Array(n.expectations.enumerated()), id: \.offset) { _, e in
                        VStack(alignment: .leading, spacing: 4) {
                            if !e.description.isEmpty { Text(e.description).bold() }
                            Text(e.message).font(.code).textSelection(.enabled)
                            if let c = e.comparison { comparison(c) }
                            if !e.caller.isEmpty { stackText(e.caller, node: n) }
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    }
                    if !n.errorStack.isEmpty {
                        Text(L10n.tr("Stos błędu")).font(.uiSecondary.bold())
                        stackText(n.errorStack, node: n)
                    }
                    if !n.serverOutput.isEmpty {
                        Text("DBMS_OUTPUT").font(.uiSecondary.bold())
                        Text(n.serverOutput).font(.code).textSelection(.enabled)
                    }
                    if !n.warnings.isEmpty {
                        Text(L10n.tr("Ostrzeżenia")).font(.uiSecondary.bold())
                        Text(n.warnings).font(.code)
                    }
                } else {
                    Text(L10n.tr("Wybierz test, żeby zobaczyć szczegóły.")).foregroundStyle(.secondary)
                    if !run.errorStack.isEmpty { Text(run.errorStack).font(.code) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(6)
        }
    }

    /// Stos z liniami `"OWNER.UNIT", line n` — każda klikalna (przejście do linii źródła).
    private func stackText(_ text: String, node: UtNode) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                if let frame = TestRunner.errorStack("ORA-06512: at " + line.replacingOccurrences(of: "ORA-06512: at ", with: "")).first, !frame.unit.isEmpty {
                    Button(line) { openFrame(frame) }.buttonStyle(.link).font(.code)
                } else {
                    Text(line).font(.code).textSelection(.enabled)
                }
            }
        }
    }

    private func openFrame(_ f: ErrorStackFrame) {
        Task {
            // Linie w stosie odnoszą się do ciała pakietu.
            try? await workspace.openObject(DBObject(owner: f.owner, name: f.unit, type: .packageBody), line: f.line)
            NSApp.mainWindow?.makeKeyAndOrderFront(nil)
        }
    }

    private func openSource(_ n: UtNode, line: Int) {
        guard !n.objectName.isEmpty else { return }
        Task {
            try? await workspace.openObject(DBObject(owner: n.owner, name: n.objectName, type: .packageBody), line: line)
            NSApp.mainWindow?.makeKeyAndOrderFront(nil)
        }
    }

    /// Raport pokrycia w oknie aplikacji (bez JavaScriptu i zasobów z sieci; strona zawiera kod źródłowy z bazy),
    /// bez pliku tymczasowego otwieranego w przeglądarce.
    private func openCoverage() {
        guard let html = run.coverageHTML else { return }
        workspace.ui?.showHTMLReport(title: L10n.tr("Raport pokrycia"), html: UtplsqlRunner.localCoverageDocument(html))
    }

    private func color(_ s: UtStatus) -> Color { UtNodeRow.color(s) }
}


/// Wiersz drzewa wyników — suity rozwinięte domyślnie.
struct UtNodeRow: View {
    let node: UtNode
    let workspace: Workspace
    let open: (UtNode) -> Void
    @State private var expanded = true

    var body: some View {
        if let children = node.children, !children.isEmpty {
            DisclosureGroup(isExpanded: $expanded) {
                ForEach(children) { UtNodeRow(node: $0, workspace: workspace, open: open) }
            } label: { label }
        } else {
            label
        }
    }

    private var label: some View {
        HStack(spacing: 6) {
            Image(systemName: Self.icon(node.status)).foregroundStyle(Self.color(node.status))
            Text(node.title).lineLimit(1)
            Spacer()
            if let t = node.executionTime { Text(String(format: "%.3f s", t)).font(.uiSecondary).foregroundStyle(.secondary) }
        }
        .tag(node.id)
        .contextMenu {
            Button(L10n.tr("Uruchom")) { workspace.perform("utplsql.runPath", CommandArguments(["path": .string(node.runPath)])) }
            Button(L10n.tr("Uruchom z pokryciem")) { workspace.perform("utplsql.runPath", CommandArguments(["path": .string(node.runPath), "coverage": .bool(true)])) }
            Button(L10n.tr("Otwórz źródło testu")) { open(node) }
        }
    }

    static func icon(_ s: UtStatus) -> String {
        switch s {
        case .pending: "circle"
        case .running: "arrow.triangle.2.circlepath"
        case .success: "checkmark.circle.fill"
        case .failure: "xmark.circle.fill"
        case .error: "exclamationmark.octagon.fill"
        case .disabled: "minus.circle"
        }
    }

    static func color(_ s: UtStatus) -> Color {
        switch s {
        case .success: .green
        case .failure: .orange
        case .error: .red
        default: .secondary
        }
    }
}
