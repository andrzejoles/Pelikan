import AppKit
import PelikanWorkspace
import SwiftUI
import UniformTypeIdentifiers

/// Okno projektu (UG 14, PD-PROJ-001..003): elementy w grupach, dodawanie plików/obiektów/notatek, opcje, Build/Make
/// z wynikami, wyszukiwanie w projekcie, pulpit.
struct ProjectView: View {
    let workspace: Workspace
    @State private var selection: ProjectItem.ID?
    @State private var findText = ""
    @State private var matches: [ProjectMatch] = []
    @State private var message = ""
    @State private var git: ProjectGitStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(L10n.tr("Nowy…")) { newProject() }
                Button(L10n.tr("Otwórz…")) { openProject() }
                Button(L10n.tr("Zamknij")) { workspace.perform("project.close") }.disabled(workspace.project == nil)
                Spacer()
                Button(L10n.tr("Buduj")) { run("project.build") }.disabled(workspace.project == nil)
                Button(L10n.tr("Make")) { run("project.make") }.disabled(workspace.project == nil)
            }
            if let p = workspace.project {
                HStack {
                    Text(p.name).font(.uiHeadline)
                    if let g = git, let branch = g.branch {
                        Label(branch + (g.ahead > 0 ? " ↑\(g.ahead)" : "") + (g.behind > 0 ? " ↓\(g.behind)" : ""), systemImage: "arrow.triangle.branch")
                            .font(.uiSecondary).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { refreshGit() } label: { Image(systemName: "arrow.clockwise") }.iconLabel(L10n.tr("Odśwież stan Git"))
                }
                HStack {
                    Button(L10n.tr("Dodaj pliki…")) { addFiles() }
                    Button(L10n.tr("Dodaj zaznaczony obiekt")) { workspace.perform("project.addSelectedObject") }.disabled(workspace.selectedObject == nil)
                    Button(L10n.tr("Dodaj notatkę")) { run("project.addNote") }
                    Button(L10n.tr("Usuń")) { if let id = selection { perform("project.removeItem", item: id) } }.disabled(selection == nil)
                    Spacer()
                    Button(L10n.tr("Zapisz pulpit")) { workspace.perform("project.saveDesktop") }
                    Button(L10n.tr("Otwórz pulpit")) { workspace.perform("project.openDesktop") }
                }
                List(selection: $selection) {
                    ForEach([nil] + p.groups.map { Optional($0) }, id: \.self) { group in
                        let items = p.items.filter { $0.group == group }
                        if !items.isEmpty {
                            Section(group ?? L10n.tr("Bez grupy")) {
                                ForEach(items) { item in row(item).tag(item.id) }
                            }
                        }
                    }
                }
                .accessibilityLabel(L10n.tr("Elementy projektu"))
                .contextMenu(forSelectionType: ProjectItem.ID.self) { _ in } primaryAction: { ids in if let id = ids.first { open(id) } }
                optionsView(p)
                HStack {
                    TextField(L10n.tr("Szukaj w projekcie"), text: $findText).textFieldStyle(.roundedBorder).onSubmit { find() }
                    Button(L10n.tr("Szukaj")) { find() }
                }
                if !matches.isEmpty {
                    List(matches) { m in
                        Text("\(m.title):\(m.line)  \(m.text)").font(.code).lineLimit(1)
                            .onTapGesture(count: 2) { open(m.item, line: m.line) }
                    }
                    .frame(height: 120)
                }
                if !workspace.projectBuildResults.isEmpty {
                    List(workspace.projectBuildResults) { r in
                        VStack(alignment: .leading) {
                            Text("\(statusText(r.status)) — \(r.title)").foregroundStyle(r.status == .failed ? .red : r.status == .skipped ? .secondary : .primary)
                            ForEach(r.messages, id: \.self) { Text($0).font(.code) }
                        }
                    }
                    .frame(height: 140)
                }
            } else {
                Text(L10n.tr("Brak otwartego projektu")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text(message).font(.uiSecondary).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(minWidth: 560, minHeight: 520)
        .onAppear { refreshGit() }
        .onChange(of: workspace.projectURL) { refreshGit() }
    }

    private func refreshGit() {
        guard let p = workspace.project, let url = workspace.projectURL else { git = nil; return }
        Task { git = await Task.detached { ProjectEngine.gitStatus(of: p, projectURL: url) }.value }
    }

    private func gitColor(_ s: GitFileState) -> Color {
        switch s {
        case .modified, .renamed: .orange
        case .added: .green
        case .deleted, .conflicted: .red
        case .untracked: .blue
        default: .secondary
        }
    }

    private func row(_ item: ProjectItem) -> some View {
        HStack {
            Image(systemName: item.kind == .file ? "doc.text" : item.kind == .object ? "cylinder" : "note.text")
            if item.kind == .note {
                CommitTextField(title: "", value: item.note ?? "") { perform("project.setNote", item: item.id, ["text": .string($0)]) }
            } else {
                Text(item.title)
            }
            if let s = git?.items[item.id], !s.badge.isEmpty {
                Text(s.badge).font(.code.bold()).foregroundStyle(gitColor(s)).help(s.displayName)
            }
            Spacer()
            CommitTextField(title: L10n.tr("grupa"), value: item.group ?? "") { perform("project.setItemGroup", item: item.id, ["group": .string($0)]) }
                .frame(width: 110).font(.uiSecondary)
        }
    }

    private func optionsView(_ p: Project) -> some View {
        HStack {
            Picker(L10n.tr("Połączenie"), selection: Binding(get: { p.options.connection ?? "" }, set: { setOption("connection", .string($0)) })) {
                Text(L10n.tr("Główne")).tag("")
                ForEach(workspace.connections.connections) { Text($0.displayName).tag($0.displayName) }
            }
            .frame(maxWidth: 280)
            Toggle(L10n.tr("Zatrzymaj po pierwszym błędzie"), isOn: Binding(get: { p.options.haltOnFirstError }, set: { setOption("haltOnFirstError", .bool($0)) }))
            Toggle(L10n.tr("Formatuj przy budowaniu"), isOn: Binding(get: { p.options.beautifyOnBuild }, set: { setOption("beautifyOnBuild", .bool($0)) }))
        }
        .toggleStyle(.checkbox).font(.uiSecondary)
    }

    private func statusText(_ s: ProjectBuildResult.Status) -> String {
        switch s {
        case .compiled: L10n.tr("skompilowano")
        case .skipped: L10n.tr("aktualne — pominięto")
        case .failed: L10n.tr("błędy")
        }
    }

    private func run(_ id: CommandID, _ arguments: CommandArguments = .empty) {
        Task {
            do { message = try await workspace.invoke(id, arguments).message ?? "" } catch CommandError.cancelledByUser {
            } catch { message = error.localizedDescription }
        }
    }

    /// Czynność na elemencie projektu po identyfikatorze — element mógł zniknąć (np. usunięty przy edycji pola notatki).
    private func perform(_ id: CommandID, item: ProjectItem.ID, _ extra: [String: JSONValue] = [:]) {
        guard workspace.project?.items.contains(where: { $0.id == item }) == true else { return }
        run(id, CommandArguments(extra.merging(["item": .string(item.uuidString)]) { _, new in new }))
    }

    private func setOption(_ option: String, _ value: JSONValue) {
        run("project.setOption", CommandArguments(["option": .string(option), "value": value]))
    }

    private func newProject() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "projekt.prj"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        workspace.perform("project.new", CommandArguments(["file": .string(url.path)]))
    }

    private func openProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "prj") ?? .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        workspace.perform("project.open", CommandArguments(["file": .string(url.path)]))
    }

    private func addFiles() {
        guard let url = workspace.projectURL else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.directoryURL = url.deletingLastPathComponent()
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        run("project.addFiles", CommandArguments(["files": .array(panel.urls.map { .string($0.path) })]))
    }

    private func open(_ id: ProjectItem.ID, line: Int = 0) {
        guard let p = workspace.project, let url = workspace.projectURL, let item = p.items.first(where: { $0.id == id }) else { return }
        Task {
            switch item.kind {
            case .file:
                if let f = ProjectEngine.url(of: item, projectURL: url), let d = try? workspace.openFile(f), line > 0 {
                    let off = d.offset(line: line, inFile: f)
                    d.selectedRange = off..<off
                }
            case .object:
                // Obiekt projektu z bazy projektu (opcja „Połączenie”), nie z połączenia aktywnego okna.
                if let o = item.object?.dbObject { try? await workspace.openObject(o, line: line, connection: (try? ProjectEngine.connection(p, in: workspace))?.id) }
            case .note:
                break
            }
        }
    }

    private func find() {
        Task {
            guard let p = workspace.project, let url = workspace.projectURL else { return }
            do {
                matches = try await ProjectEngine.find(findText, in: p, projectURL: url, ws: workspace)
                message = L10n.tr("Trafienia: \(matches.count)")
            } catch { message = error.localizedDescription }
        }
    }
}

/// Pole tekstowe zatwierdzane Enterem albo przy utracie fokusu (projekt, biblioteka makr) — zmiana idzie komendą raz,
/// a nie przy każdym znaku; bez edycji pole pokazuje bieżącą wartość.
struct CommitTextField: View {
    let title: String
    let value: String
    let commit: (String) -> Void
    @State private var draft: String?
    @FocusState private var focused: Bool

    var body: some View {
        TextField(title, text: Binding(get: { draft ?? value }, set: { draft = $0 }))
            .focused($focused)
            .onSubmit(save)
            .onChange(of: focused) { if !focused { save() } }
    }

    private func save() {
        guard let d = draft else { return }
        draft = nil
        if d != value { commit(d) }
    }
}
