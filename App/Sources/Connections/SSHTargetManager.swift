import AppKit
import PelikanProC
import PelikanRemote
import PelikanWorkspace
import SwiftUI

/// Stan menedżera celów SSH (zdalny build Pro*C): zaznaczenie w drzewie, szkic edytowanego celu, sekret tylko
/// w pamięci do zapisu (potem Pęk kluczy albo pamięć sesji), wyniki „Testuj”.
@MainActor
@Observable
final class SSHTargetManagerModel {
    let store: SSHTargetStore
    let workspace: Workspace
    let runDirectory: URL
    var selection: String?
    var draft: PelikanSSHTarget?
    var secret = ""
    var rememberSecret = true
    var checks: [SSHTestCheck] = []
    var testing = false
    var message: String?

    init(store: SSHTargetStore, workspace: Workspace, runDirectory: URL) {
        self.store = store
        self.workspace = workspace
        self.runDirectory = runDirectory
    }

    struct Node: Identifiable, Hashable {
        var id: String
        var title: String
        var environment: SSHTargetEnvironment?
        var children: [Node]?
    }

    /// Drzewo: foldery (z podfolderami) i cele; klucz zaznaczenia `f:<id>` / `t:<id>`.
    var nodes: [Node] {
        func level(_ parent: UUID?) -> [Node] {
            let folders = store.folders.filter { $0.parentID == parent }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            let targets = store.targets.filter { $0.folderID == parent }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return folders.map { Node(id: "f:\($0.id)", title: $0.name, children: level($0.id)) }
                + targets.map { Node(id: "t:\($0.id)", title: $0.name, environment: $0.environment) }
        }
        return level(nil)
    }

    var selectedTargetID: UUID? { selection.flatMap { $0.hasPrefix("t:") ? UUID(uuidString: String($0.dropFirst(2))) : nil } }
    var selectedFolderID: UUID? { selection.flatMap { $0.hasPrefix("f:") ? UUID(uuidString: String($0.dropFirst(2))) : nil } }

    func selectionChanged() {
        draft = selectedTargetID.flatMap(store.target)
        secret = ""
        checks = []
        message = nil
    }

    func select(name: String) {
        guard let t = store.targets.first(where: { $0.name == name }) else { return }
        selection = "t:\(t.id)"
        selectionChanged()
    }

    func addTarget() {
        var t = PelikanSSHTarget(name: L10n.tr("Nowy cel"), host: "", user: NSUserName(), baseDirectory: "", backupDirectory: "")
        t.folderID = selectedFolderID ?? draft?.folderID
        draft = t
        selection = nil
        secret = ""
        checks = []
    }

    func addFolder() {
        let f = SSHTargetFolder(name: L10n.tr("Nowy folder"), parentID: selectedFolderID)
        report { try store.upsert(folder: f) }
        selection = "f:\(f.id)"
    }

    func renameFolder(_ id: UUID, to name: String) {
        guard var f = store.folders.first(where: { $0.id == id }), !name.isEmpty else { return }
        f.name = name
        report { try store.upsert(folder: f) }
    }

    func duplicate() {
        guard let id = selectedTargetID else { return }
        report {
            if let c = try store.duplicate(id) { selection = "t:\(c.id)"; selectionChanged() }
        }
    }

    func delete() {
        if let id = selectedTargetID, let t = store.target(id) {
            let alert = NSAlert()
            alert.messageText = L10n.tr("Usunąć cel „\(t.name)”?")
            alert.informativeText = L10n.tr("Zapisany sekret celu zostanie usunięty z Pęku kluczy.")
            alert.addButton(withTitle: L10n.tr("Usuń"))
            alert.addButton(withTitle: L10n.tr("Anuluj"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            report { try store.remove(id) }
        } else if let id = selectedFolderID {
            report { try store.remove(folder: id) }
        }
        selection = nil
        selectionChanged()
    }

    func save() {
        guard var t = draft else { return }
        if t.backupDirectory.isEmpty, !t.baseDirectory.isEmpty { t.backupDirectory = PelikanSSHTarget.suggestedBackupDirectory(base: t.baseDirectory) }
        draft = t
        guard t.validationErrors.isEmpty else { message = t.validationErrors.joined(separator: "\n"); return }
        report {
            try store.upsert(t, secret: secret.isEmpty || t.auth == .agent ? nil : secret, remember: rememberSecret)
            secret = ""
            selection = "t:\(t.id)"
            message = L10n.tr("Zapisano")
        }
    }

    private func report(_ body: () throws -> Void) {
        do { try body() } catch { message = error.localizedDescription }
    }

    /// „Testuj” w tle (ssh przez posix_spawn); brak katalogu backupów — utworzenie po potwierdzeniu (PROD: nazwą celu).
    func test() async {
        guard let t = draft, !testing else { return }
        testing = true
        checks = []
        message = nil
        defer { testing = false }
        let secret: String?
        do {
            if t.auth == .agent { secret = nil } else if !self.secret.isEmpty { secret = self.secret } else { secret = try await store.secret(for: t.id, in: workspace) }
        } catch {
            message = L10n.tr("Anulowano")
            return
        }
        let run = runDirectory
        let result: Result<[SSHTestCheck], any Error> = await Task.detached {
            do {
                let s = try SSHSession(config: SSHTargetTester.sessionConfig(t), runDirectory: run, secret: { secret })
                defer { s.disconnect() }
                return .success(SSHTargetTester.run(t, session: s))
            } catch { return .failure(error) }
        }.value
        switch result {
        case .success(let c): checks = c
        case .failure(let e): message = SSHTargetTester.describe(e); return
        }
        guard checks.first(where: { $0.title == L10n.tr("Katalog backupów") })?.status == .failed,
              checks.first(where: { $0.title == L10n.tr("Logowanie") })?.status == .ok else { return }
        let alert = NSAlert()
        alert.messageText = L10n.tr("Utworzyć katalog backupów?")
        alert.informativeText = t.backupDirectory
        alert.addButton(withTitle: L10n.tr("Utwórz"))
        alert.addButton(withTitle: L10n.tr("Nie"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard await ProductionConfirmation.confirm(t, operation: L10n.tr("utworzenie katalogu backupów"), ask: SSHTargetPrompts.askTargetName) else {
            message = L10n.tr("Nie potwierdzono nazwy celu PROD")
            return
        }
        let created: String? = await Task.detached {
            do {
                let s = try SSHSession(config: SSHTargetTester.sessionConfig(t), runDirectory: run, secret: { secret })
                defer { s.disconnect() }
                try SSHTargetTester.createBackupDirectory(t, session: s)
                return nil
            } catch { return SSHTargetTester.describe(error) }
        }.value
        message = created ?? L10n.tr("Utworzono katalog backupów")
    }
}

/// Pytania menedżera celów SSH.
@MainActor
enum SSHTargetPrompts {
    /// Potwierdzenie operacji na PROD: pole na nazwę celu (nil — anulowano).
    static func askTargetName(_ message: String) async -> String? {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = L10n.tr("Cel produkcyjny")
        alert.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.placeholderString = L10n.tr("Nazwa celu")
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.tr("Kontynuuj"))
        alert.addButton(withTitle: L10n.tr("Anuluj"))
        alert.window.initialFirstResponder = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }
}

extension SSHTargetEnvironment {
    var color: Color { self == .prod ? .red : .orange }
}

/// Menedżer celów SSH w stylu menedżera połączeń: drzewo z folderami po lewej, edycja i „Testuj” po prawej.
struct SSHTargetManagerView: View {
    @Bindable var model: SSHTargetManagerModel

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(model.nodes, children: \.children, selection: $model.selection) { node in
                    HStack(spacing: 6) {
                        Image(systemName: node.children == nil ? "server.rack" : "folder")
                        Text(node.title)
                        if let env = node.environment {
                            Spacer()
                            Text(env.rawValue).font(.caption2.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 5).background(env.color, in: RoundedRectangle(cornerRadius: 3))
                        }
                    }
                }
                .onChange(of: model.selection) { model.selectionChanged() }
                Divider()
                HStack(spacing: 4) {
                    Button { model.addTarget() } label: { Image(systemName: "plus") }.iconLabel(L10n.tr("Dodaj cel"))
                    Button { model.addFolder() } label: { Image(systemName: "folder.badge.plus") }.iconLabel(L10n.tr("Dodaj folder"))
                    Button { model.duplicate() } label: { Image(systemName: "plus.square.on.square") }.iconLabel(L10n.tr("Duplikuj"))
                        .disabled(model.selectedTargetID == nil)
                    Button { model.delete() } label: { Image(systemName: "minus") }.iconLabel(L10n.tr("Usuń"))
                        .disabled(model.selection == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(minWidth: 200, idealWidth: 240)

            VStack(alignment: .leading, spacing: 0) {
                if let folderID = model.selectedFolderID, let folder = model.store.folders.first(where: { $0.id == folderID }) {
                    Form {
                        TextField(L10n.tr("Nazwa folderu"), text: Binding(get: { folder.name }, set: { model.renameFolder(folderID, to: $0) }))
                    }
                    .padding()
                    Spacer()
                } else if model.draft != nil {
                    SSHTargetEditor(model: model)
                } else {
                    Text(L10n.tr("Wybierz cel albo dodaj nowy")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 520)
        }
        .frame(minWidth: 760, minHeight: 520)
    }
}

/// Formularz celu z wynikami „Testuj”.
struct SSHTargetEditor: View {
    @Bindable var model: SSHTargetManagerModel

    private var draft: Binding<PelikanSSHTarget> {
        Binding(get: { model.draft ?? PelikanSSHTarget(name: "", host: "", user: "", baseDirectory: "", backupDirectory: "") },
                set: { model.draft = $0 })
    }

    /// Zmienne dodatkowe jako wiersze `NAZWA=wartość`.
    private var extraEnvironment: Binding<String> {
        Binding(get: { draft.wrappedValue.extraEnvironment.map { "\($0.name)=\($0.value)" }.joined(separator: "\n") },
                set: { text in
                    draft.wrappedValue.extraEnvironment = text.split(separator: "\n").compactMap { line in
                        guard let eq = line.firstIndex(of: "=") else { return nil }
                        return SSHEnvironmentVariable(name: line[..<eq].trimmingCharacters(in: .whitespaces), value: String(line[line.index(after: eq)...]))
                    }
                })
    }

    private var binaries: Binding<String> {
        Binding(get: { draft.wrappedValue.binaries.joined(separator: ", ") },
                set: { draft.wrappedValue.binaries = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } })
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(L10n.tr("Połączenie")) {
                    TextField(L10n.tr("Nazwa"), text: draft.name)
                    Picker(L10n.tr("Folder"), selection: draft.folderID) {
                        Text(L10n.tr("(brak)")).tag(UUID?.none)
                        ForEach(model.store.folders) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker(L10n.tr("Środowisko"), selection: draft.environment) {
                        ForEach(SSHTargetEnvironment.allCases, id: \.self) { Text($0.rawValue).foregroundStyle($0.color).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        TextField(L10n.tr("Host"), text: draft.host)
                        TextField(L10n.tr("Port"), value: draft.port, format: .number.grouping(.never)).frame(width: 80)
                    }
                    TextField(L10n.tr("Użytkownik"), text: draft.user)
                    Picker(L10n.tr("Uwierzytelnianie"), selection: draft.auth) {
                        Text(L10n.tr("Plik klucza")).tag(SSHAuthMethod.keyFile)
                        Text(L10n.tr("Agent SSH")).tag(SSHAuthMethod.agent)
                        Text(L10n.tr("Hasło SSH")).tag(SSHAuthMethod.password)
                    }
                    if draft.wrappedValue.auth == .keyFile {
                        HStack {
                            TextField(L10n.tr("Plik klucza"), text: draft.keyFile)
                            Button(L10n.tr("Wybierz…")) {
                                let panel = NSOpenPanel()
                                panel.showsHiddenFiles = true
                                if panel.runModal() == .OK, let u = panel.url { draft.wrappedValue.keyFile = u.path }
                            }
                        }
                    }
                    if draft.wrappedValue.auth != .agent {
                        SecureField(draft.wrappedValue.auth == .password ? L10n.tr("Hasło SSH") : L10n.tr("Hasło klucza (opcjonalne)"), text: $model.secret,
                                    prompt: Text(model.store.hasSecret(for: draft.wrappedValue.id) ? L10n.tr("zapisane — wpisz, aby zmienić") : ""))
                        Toggle(L10n.tr("Zapamiętaj w Pęku kluczy"), isOn: $model.rememberSecret)
                    }
                    Toggle(L10n.tr("Stare algorytmy (AIX 6.1 i starsze serwery)"), isOn: draft.legacyAlgorithms)
                    Picker(L10n.tr("Kodowanie nazw"), selection: draft.nameEncoding) {
                        ForEach(NameEncoding.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    Picker(L10n.tr("Kodowanie konsoli"), selection: draft.consoleEncoding) {
                        ForEach(NameEncoding.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                }
                Section(L10n.tr("Katalogi na serwerze")) {
                    TextField(L10n.tr("Katalog bazowy"), text: draft.baseDirectory, prompt: Text("/…/app"))
                    TextField(L10n.tr("Katalog backupów"), text: draft.backupDirectory,
                              prompt: Text(PelikanSSHTarget.suggestedBackupDirectory(base: draft.wrappedValue.baseDirectory.isEmpty ? "/…/app" : draft.wrappedValue.baseDirectory)))
                    TextField(L10n.tr("Working copy"), text: draft.workingCopyDirectory, prompt: Text(draft.wrappedValue.sourceDirectory))
                    DisclosureGroup(L10n.tr("Zaawansowane")) {
                        TextField(L10n.tr("Podkatalog źródeł"), text: draft.sourceFolderName)
                        TextField(L10n.tr("Podkatalog binarek"), text: draft.binaryFolderName)
                        LabeledContent(L10n.tr("Katalog roboczy Pelikana"), value: draft.wrappedValue.pelikanDirectory)
                    }
                }
                Section(L10n.tr("Git i build")) {
                    TextField(L10n.tr("Gałąź"), text: draft.branch)
                    TextField(L10n.tr("Remote"), text: draft.remote)
                    TextField(L10n.tr("Komenda builda"), text: draft.buildCommand)
                    TextField(L10n.tr("Binarki (po przecinku)"), text: binaries, prompt: Text(draft.wrappedValue.name))
                }
                Section(L10n.tr("Środowisko powłoki")) {
                    TextField(L10n.tr("Powłoka ksh"), text: draft.kshPath)
                    TextField("ORACLE_HOME", text: draft.oracleHome)
                    TextField("LIBPATH", text: draft.libPath)
                    TextField("PATH", text: draft.path)
                    VStack(alignment: .leading) {
                        Text(L10n.tr("Dodatkowe zmienne (NAZWA=wartość, po jednej w wierszu)")).font(.caption)
                        TextEditor(text: extraEnvironment).font(.system(.body, design: .monospaced)).frame(height: 54)
                    }
                }
                if !model.checks.isEmpty {
                    Section(L10n.tr("Wynik testu")) {
                        ForEach(model.checks) { c in
                            HStack(alignment: .firstTextBaseline) {
                                Image(systemName: c.status == .ok ? "checkmark.circle.fill" : c.status == .warning ? "exclamationmark.triangle.fill" : "xmark.octagon.fill")
                                    .foregroundStyle(c.status == .ok ? .green : c.status == .warning ? .orange : .red)
                                Text(c.title).frame(width: 150, alignment: .leading)
                                Text(c.detail).textSelection(.enabled).lineLimit(4).font(.system(.callout, design: .monospaced))
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                if let m = model.message { Text(m).foregroundStyle(.secondary).lineLimit(3) }
                Spacer()
                if model.testing { ProgressView().controlSize(.small) }
                Button(L10n.tr("Testuj")) { Task { await model.test() } }.disabled(model.testing || draft.wrappedValue.host.isEmpty)
                Button(L10n.tr("Zapisz")) { model.save() }.keyboardShortcut(.defaultAction)
            }
            .padding(10)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(draft.wrappedValue.environment.color).frame(height: 3)
        }
    }
}
