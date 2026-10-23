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
                    Text(p.name).font(.headline)
                    if let g = git, let branch = g.branch {
                        Label(branch + (g.ahead > 0 ? " ↑\(g.ahead)" : "") + (g.behind > 0 ? " ↓\(g.behind)" : ""), systemImage: "arrow.triangle.branch")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { refreshGit() } label: { Image(systemName: "arrow.clockwise") }.help(L10n.tr("Odśwież stan Git"))
                }
                HStack {
                    Button(L10n.tr("Dodaj pliki…")) { addFiles() }
                    Button(L10n.tr("Dodaj zaznaczony obiekt")) { workspace.perform("project.addSelectedObject") }.disabled(workspace.selectedObject == nil)
                    Button(L10n.tr("Dodaj notatkę")) { mutate { $0.items.append(.note(L10n.tr("Notatka"))) } }
                    Button(L10n.tr("Usuń")) { mutate { p in p.items.removeAll { $0.id == selection } } }.disabled(selection == nil)
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
                .contextMenu(forSelectionType: ProjectItem.ID.self) { _ in } primaryAction: { ids in if let id = ids.first { open(id) } }
                optionsView(p)
                HStack {
                    TextField(L10n.tr("Szukaj w projekcie"), text: $findText).textFieldStyle(.roundedBorder).onSubmit { find() }
                    Button(L10n.tr("Szukaj")) { find() }
                }
                if !matches.isEmpty {
                    List(matches) { m in
                        Text("\(m.title):\(m.line)  \(m.text)").font(.system(size: 11, design: .monospaced)).lineLimit(1)
                            .onTapGesture(count: 2) { open(m.item, line: m.line) }
                    }
                    .frame(height: 120)
                }
                if !workspace.projectBuildResults.isEmpty {
                    List(workspace.projectBuildResults) { r in
                        VStack(alignment: .leading) {
                            Text("\(statusText(r.status)) — \(r.title)").foregroundStyle(r.status == .failed ? .red : r.status == .skipped ? .secondary : .primary)
                            ForEach(r.messages, id: \.self) { Text($0).font(.caption.monospaced()) }
                        }
                    }
                    .frame(height: 140)
                }
            } else {
                Text(L10n.tr("Brak otwartego projektu")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text(message).font(.caption).foregroundStyle(.secondary)
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
            if item.kind == .note, let i = workspace.project?.items.firstIndex(where: { $0.id == item.id }) {
                TextField("", text: Binding(get: { workspace.project?.items[i].note ?? "" }, set: { v in mutate { $0.items[i].note = v } }))
            } else {
                Text(item.title)
            }
            if let s = git?.items[item.id], !s.badge.isEmpty {
                Text(s.badge).font(.caption.monospaced().bold()).foregroundStyle(gitColor(s)).help(s.displayName)
            }
            Spacer()
            TextField(L10n.tr("grupa"), text: Binding(get: { item.group ?? "" }, set: { v in
                mutate { p in if let i = p.items.firstIndex(where: { $0.id == item.id }) { p.items[i].group = v.isEmpty ? nil : v } }
            }))
            .frame(width: 110).font(.caption)
        }
    }

    private func optionsView(_ p: Project) -> some View {
        HStack {
            Picker(L10n.tr("Połączenie"), selection: Binding(get: { p.options.connection ?? "" }, set: { v in mutate { $0.options.connection = v.isEmpty ? nil : v } })) {
                Text(L10n.tr("Główne")).tag("")
                ForEach(workspace.connections.connections) { Text($0.displayName).tag($0.displayName) }
            }
            .frame(maxWidth: 280)
            Toggle(L10n.tr("Zatrzymaj po pierwszym błędzie"), isOn: Binding(get: { p.options.haltOnFirstError }, set: { v in mutate { $0.options.haltOnFirstError = v } }))
            Toggle(L10n.tr("Formatuj przy budowaniu"), isOn: Binding(get: { p.options.beautifyOnBuild }, set: { v in mutate { $0.options.beautifyOnBuild = v } }))
        }
        .toggleStyle(.checkbox).font(.caption)
    }

    private func statusText(_ s: ProjectBuildResult.Status) -> String {
        switch s {
        case .compiled: L10n.tr("skompilowano")
        case .skipped: L10n.tr("aktualne — pominięto")
        case .failed: L10n.tr("błędy")
        }
    }

    private func mutate(_ change: (inout Project) -> Void) {
        guard var p = workspace.project, let url = workspace.projectURL else { return }
        change(&p)
        workspace.project = p
        try? p.encoded().write(to: url, options: .atomic)
    }

    private func run(_ id: CommandID) {
        Task {
            do { message = try await workspace.invoke(id).message ?? "" } catch { message = error.localizedDescription }
        }
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
        guard panel.runModal() == .OK else { return }
        mutate { p in
            for f in panel.urls {
                let rel = ProjectEngine.relativePath(f, projectURL: url)
                if !p.items.contains(where: { $0.path == rel }) { p.items.append(.file(rel)) }
            }
        }
    }

    private func open(_ id: ProjectItem.ID, line: Int = 0) {
        guard let p = workspace.project, let url = workspace.projectURL, let item = p.items.first(where: { $0.id == id }) else { return }
        Task {
            switch item.kind {
            case .file:
                if let f = ProjectEngine.url(of: item, projectURL: url), let d = try? workspace.openFile(f), line > 0 {
                    let off = ProgramCompiler.offset(line: line, column: 1, in: d.text)
                    d.selectedRange = off..<off
                }
            case .object:
                if let o = item.object?.dbObject { try? await workspace.openObject(o, line: line) }
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
