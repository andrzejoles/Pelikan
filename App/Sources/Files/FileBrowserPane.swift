import AppKit
import Observation
import PelikanWorkspace
import SwiftUI

/// Stan drzewa plików jednej lokalizacji: zawartość rozwiniętych katalogów, stan Git, filtr.
@MainActor
@Observable
final class FileTreeModel {
    let workspace: Workspace
    var locationID: UUID?
    var filter = FileFilter()
    var git: GitStatus?
    /// Pamięć podręczna katalogów (wypełniana podczas rysowania — bez obserwacji; zmiany sygnalizuje `generation`).
    @ObservationIgnored private var children: [String: [FileEntry]] = [:]
    /// Data modyfikacji katalogu z chwili wczytania i otwarte/zmienione dokumenty — podstawa cyklicznego odświeżania.
    @ObservationIgnored private var stamps: [String: Date] = [:]
    @ObservationIgnored private var documentState: (open: Set<String>, modified: Set<String>) = ([], [])
    @ObservationIgnored private var refreshing = false
    private(set) var generation = 0

    init(workspace: Workspace) {
        self.workspace = workspace
        locationID = workspace.fileBrowser.locations.first?.id
    }

    var location: FileLocation? { workspace.fileBrowser.locations.first { $0.id == locationID } }

    /// Wczytuje ponownie katalogi i stan Git (przycisk odświeżania, zmiana filtra, lokalizacji, operacje na plikach).
    func reload() {
        invalidate()
        guard let loc = location else { git = nil; return }
        let url = loc.url
        Task {
            let status = await Task.detached { GitRepository.discover(for: url).flatMap { try? $0.status() } }.value
            guard status != self.git else { return }
            self.git = status
            self.invalidate()
        }
    }

    /// Cykliczne odświeżanie: stan Git i daty modyfikacji wczytanych katalogów sprawdzane w tle; katalogi są
    /// listowane ponownie tylko po zmianie (zmieniony katalog, a po zmianie Git albo dokumentów — całe drzewo).
    func refresh() {
        guard let loc = location, !refreshing else { return }
        refreshing = true
        let url = loc.url
        let known = stamps
        Task {
            let (status, changed) = await Task.detached {
                (GitRepository.discover(for: url).flatMap { try? $0.status() },
                 known.filter { Self.modificationDate($0.key) != $0.value }.map(\.key))
            }.value
            self.refreshing = false
            guard self.locationID == loc.id else { return }
            let docs = self.currentDocuments()
            if status != self.git || docs != self.documentState {
                if status != self.git { self.git = status }
                self.invalidate()
            } else if !changed.isEmpty {
                for path in changed { self.children[path] = nil; self.stamps[path] = nil }
                self.generation += 1
            }
        }
    }

    private func invalidate() {
        children = [:]
        stamps = [:]
        generation += 1
    }

    private func currentDocuments() -> (open: Set<String>, modified: Set<String>) {
        (Set(workspace.documents.compactMap { $0.fileURL?.standardizedFileURL.path }),
         Set(workspace.documents.filter(\.isModified).compactMap { $0.fileURL?.standardizedFileURL.path }))
    }

    nonisolated static func modificationDate(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    func entries(of directory: URL) -> [FileEntry] {
        if let c = children[directory.path] { return c }
        let docs = currentDocuments()
        documentState = docs
        stamps[directory.path] = Self.modificationDate(directory.path)
        let list = FileBrowser.entries(in: directory, locationMask: location?.filter ?? "", filter: filter, showHidden: workspace.fileBrowser.showHidden,
                                       git: git, openFiles: docs.open, modifiedFiles: docs.modified)
        children[directory.path] = list
        return list
    }
}

/// Przeglądarka plików (UG 22, PD-FB-001/002): lokalizacje z hierarchią i kolorem, drzewo plików z filtrem i stanem
/// Git, otwieranie w oknach wg rozszerzenia, menu operacji na plikach i Git.
struct FileBrowserPane: View {
    let workspace: Workspace
    @State private var model: FileTreeModel
    @State private var nameFilter = ""
    @State private var showOptions = false
    @State private var selection: String?
    @Environment(\.controlActiveState) private var activeState

    init(workspace: Workspace) {
        self.workspace = workspace
        _model = State(initialValue: FileTreeModel(workspace: workspace))
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Picker("", selection: $model.locationID) {
                    if workspace.fileBrowser.locations.isEmpty { Text(L10n.tr("Brak lokalizacji")).tag(UUID?.none) }
                    ForEach(flatLocations(), id: \.0.id) { loc, depth in
                        Text(String(repeating: "   ", count: depth) + loc.name).tag(Optional(loc.id))
                    }
                }
                .labelsHidden()
                Button { workspace.perform("fb.addLocation") } label: { Image(systemName: "plus") }
                    .iconLabel(L10n.tr("Dodaj lokalizację…"))
                Menu {
                    if let loc = model.location {
                        Button(L10n.tr("Usuń lokalizację „\(loc.name)”")) {
                            workspace.perform("fb.removeLocation", CommandArguments(["location": .string(loc.id.uuidString)]))
                            model.locationID = workspace.fileBrowser.locations.first?.id
                        }
                    }
                    Toggle(L10n.tr("Pokaż ukryte pliki"), isOn: Binding(get: { workspace.fileBrowser.showHidden },
                                                                       set: { workspace.fileBrowser.showHidden = $0; model.reload() }))
                    Button(L10n.tr("Wyczyść historię filtra")) { workspace.perform("fb.clearFilterHistory") }
                } label: { Image(systemName: "ellipsis.circle") }.iconLabel(L10n.tr("Więcej"))
                    .menuIndicator(.hidden)
                    .fixedSize()
                Button { model.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .iconLabel(L10n.tr("Odśwież"))
            }
            .padding(.horizontal, 8)
            filterBar
            if let loc = model.location {
                List(selection: $selection) {
                    FileTreeLevel(model: model, directory: loc.url, workspace: workspace)
                }
                .listStyle(.sidebar)
                .accessibilityLabel(L10n.tr("File Browser"))
                .contextMenu(forSelectionType: String.self) { ids in
                    if let path = ids.first { menu(for: URL(fileURLWithPath: path)) }
                } primaryAction: { ids in
                    if let path = ids.first { open(URL(fileURLWithPath: path), as: nil) }
                }
                .overlay(alignment: .bottomLeading) {
                    if let g = model.git {
                        Label(g.branch ?? L10n.tr("(odłączony HEAD)"), systemImage: "arrow.triangle.branch")
                            .font(.uiSecondary).foregroundStyle(.secondary).padding(6)
                    }
                }
            } else {
                Spacer()
                Text(L10n.tr("Dodaj katalog jako lokalizację (+)")).foregroundStyle(.secondary).font(.ui)
                Spacer()
            }
        }
        .padding(.bottom, 6)
        .onChange(of: model.locationID) { model.reload() }
        .onAppear { model.reload() }
        // Odświeżanie co 5 s (git status, daty katalogów) tylko przy widocznej karcie Pliki (zadanie kończy się, gdy
        // karta znika z okna) i aktywnej aplikacji — wcześniej zegar odpytywał git przez cały czas działania aplikacji.
        .task(id: activeState == .inactive) {
            guard activeState != .inactive else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                model.refresh()
            }
        }
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                TextField(L10n.tr("Filtr nazw (maski *.sql;*.pck)"), text: $nameFilter)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { applyFilter() }
                Menu {
                    ForEach(workspace.fileBrowser.filterHistory, id: \.self) { h in Button(h) { nameFilter = h; applyFilter() } }
                } label: { Image(systemName: "clock") }.iconLabel(L10n.tr("Historia filtra"))
                    .menuIndicator(.hidden).fixedSize().disabled(workspace.fileBrowser.filterHistory.isEmpty)
                Button { showOptions.toggle() } label: { Image(systemName: model.filter.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill") }
                    .iconLabel(L10n.tr("Filtr: stan, Git, rozmiar, data"))
            }
            if showOptions {
                Picker(L10n.tr("Stan"), selection: $model.filter.status) {
                    Text(L10n.tr("dowolny")).tag(FileFilter.Status.any)
                    Text(L10n.tr("otwarte")).tag(FileFilter.Status.open)
                    Text(L10n.tr("zmienione")).tag(FileFilter.Status.modified)
                }
                Menu(L10n.tr("Git: ") + (model.filter.vcs.isEmpty ? L10n.tr("dowolny") : model.filter.vcs.map(\.displayName).sorted().joined(separator: ", "))) {
                    ForEach(GitFileState.allCases, id: \.self) { s in
                        Toggle(s.displayName, isOn: Binding(get: { model.filter.vcs.contains(s) },
                                                            set: { if $0 { model.filter.vcs.insert(s) } else { model.filter.vcs.remove(s) } }))
                    }
                }
                HStack {
                    Text(L10n.tr("Rozmiar (kB)"))
                    TextField(L10n.tr("od"), value: kb(\.minSize), format: .number).frame(width: 60)
                    TextField(L10n.tr("do"), value: kb(\.maxSize), format: .number).frame(width: 60)
                }
                HStack {
                    Text(L10n.tr("Zmienione w ostatnich dniach"))
                    TextField("", value: Binding(get: { model.filter.modifiedAfter.map { Int(-$0.timeIntervalSinceNow / 86_400) } },
                                                 set: { model.filter.modifiedAfter = $0.map { Date().addingTimeInterval(-Double($0) * 86_400) } }),
                              format: .number).frame(width: 60)
                }
                Button(L10n.tr("Wyczyść filtr")) { model.filter = FileFilter(); nameFilter = "" }
            }
        }
        .font(.ui)
        .padding(.horizontal, 8)
        .onChange(of: model.filter) { model.reload() }
    }

    private func kb(_ key: WritableKeyPath<FileFilter, Int64?>) -> Binding<Int?> {
        Binding(get: { model.filter[keyPath: key].map { Int($0 / 1024) } }, set: { model.filter[keyPath: key] = $0.map { Int64($0) * 1024 } })
    }

    private func applyFilter() {
        model.filter.name = nameFilter
        workspace.fileBrowser.remember(filter: nameFilter)
    }

    private func flatLocations() -> [(FileLocation, Int)] {
        func walk(_ parent: UUID?, _ depth: Int) -> [(FileLocation, Int)] {
            workspace.fileBrowser.children(of: parent).flatMap { [($0, depth)] + walk($0.id, depth + 1) }
        }
        return walk(nil, 0)
    }

    private func open(_ url: URL, as kind: String?) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { return }
        var args: [String: JSONValue] = ["path": .string(url.path)]
        if let kind { args["kind"] = .string(kind) }
        workspace.perform("fb.open", CommandArguments(args))
    }

    @ViewBuilder
    private func menu(for url: URL) -> some View {
        let dir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let path = JSONValue.string(url.path)
        let parent = JSONValue.string(dir ? url.path : url.deletingLastPathComponent().path)
        if !dir {
            Button(L10n.tr("Otwórz")) { open(url, as: nil) }
            Menu(L10n.tr("Otwórz jako")) {
                Button(L10n.tr("Okno SQL")) { open(url, as: "sql") }
                Button(L10n.tr("Okno programu")) { open(url, as: "program") }
                Button(L10n.tr("Okno testu")) { open(url, as: "test") }
                Button(L10n.tr("Okno poleceń")) { open(url, as: "command") }
            }
            Divider()
        }
        Button(L10n.tr("Nowy plik…")) { workspace.perform("fb.newFile", CommandArguments(["directory": parent])); refreshSoon() }
        Button(L10n.tr("Nowy katalog…")) { workspace.perform("fb.newFolder", CommandArguments(["directory": parent])); refreshSoon() }
        Button(L10n.tr("Zmień nazwę…")) { workspace.perform("fb.rename", CommandArguments(["path": path])); refreshSoon() }
        Button(L10n.tr("Przenieś do Kosza…")) { workspace.perform("fb.trash", CommandArguments(["path": path])); refreshSoon() }
        Button(L10n.tr("Pokaż w Finderze")) { workspace.perform("fb.showInFinder", CommandArguments(["path": path])) }
        Button(L10n.tr("Dodaj jako lokalizację")) {
            workspace.perform("fb.addLocation", CommandArguments(["path": parent, "parent": model.locationID.map { .string($0.uuidString) } ?? .null]))
        }
        if model.git != nil, !dir {
            Divider()
            Button(L10n.tr("Git: porównaj z HEAD")) { workspace.perform("vcs.diff", CommandArguments(["path": path])) }
            Button(L10n.tr("Git: dodaj do zatwierdzenia")) { workspace.perform("vcs.add", CommandArguments(["path": path])); refreshSoon() }
            Button(L10n.tr("Git: zatwierdź…")) { workspace.perform("vcs.commit", CommandArguments(["path": path])); refreshSoon() }
            Button(L10n.tr("Git: historia pliku")) { workspace.perform("vcs.log", CommandArguments(["path": path])) }
        }
    }

    private func refreshSoon() {
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            model.reload()
        }
    }
}

/// Jeden poziom drzewa (katalogi rozwijane leniwie).
struct FileTreeLevel: View {
    let model: FileTreeModel
    let directory: URL
    let workspace: Workspace

    var body: some View {
        let _ = model.generation
        ForEach(model.entries(of: directory)) { e in
            if e.isDirectory {
                DisclosureGroup {
                    FileTreeLevel(model: model, directory: e.url, workspace: workspace)
                } label: {
                    Label(e.name, systemImage: "folder").tag(e.url.path)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: icon(e.name)).foregroundStyle(.secondary)
                    Text(e.name).lineLimit(1)
                    Spacer()
                    if let g = e.git, !g.badge.isEmpty {
                        Text(g.badge).font(.subheadline.monospaced().bold()).foregroundStyle(color(g)).help(g.displayName)
                    }
                }
                .tag(e.url.path)
                .help(e.url.lastPathComponent)
            }
        }
    }

    private func icon(_ name: String) -> String {
        switch DocumentKind.forFile(URL(fileURLWithPath: name)) {
        case .program: "curlybraces"
        case .test: "checkmark.seal"
        default: "doc.text"
        }
    }

    private func color(_ s: GitFileState) -> Color {
        switch s {
        case .modified, .renamed: .orange
        case .added: .green
        case .deleted, .conflicted: .red
        case .untracked: .blue
        default: .secondary
        }
    }
}

final class FileBrowserPaneController: NSViewController {
    private let workspace: Workspace
    init(workspace: Workspace) {
        self.workspace = workspace
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() { view = NSHostingView(rootView: FileBrowserPane(workspace: workspace).interfaceFont()) }
}
