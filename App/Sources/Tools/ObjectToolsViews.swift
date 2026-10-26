import AppKit
import PelikanDB
import PelikanWorkspace
import SwiftUI

/// Wybór obiektów schematu (eksport, porównanie): filtr typu i nazwy, zaznaczanie.
struct ObjectPicker: View {
    let objects: [DBObject]
    @Binding var selected: Set<DBObject>
    @State private var type: DBObjectType?
    @State private var text = ""

    private var visible: [DBObject] {
        objects.filter { (type == nil || $0.type == type) && (text.isEmpty || $0.name.localizedCaseInsensitiveContains(text)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Picker(L10n.tr("Typ"), selection: $type) {
                    Text(L10n.tr("Wszystkie")).tag(DBObjectType?.none)
                    ForEach(Array(Set(objects.map(\.type))).sorted { $0.rawValue < $1.rawValue }, id: \.self) { Text($0.rawValue).tag(DBObjectType?.some($0)) }
                }
                .frame(maxWidth: 240)
                TextField(L10n.tr("Nazwa"), text: $text).textFieldStyle(.roundedBorder)
                Button(L10n.tr("Zaznacz widoczne")) { selected.formUnion(visible) }
                Button(L10n.tr("Odznacz")) { selected.subtract(visible) }
            }
            List(visible, id: \.self) { o in
                Toggle(isOn: Binding(get: { selected.contains(o) }, set: { if $0 { selected.insert(o) } else { selected.remove(o) } })) {
                    HStack { Text(o.name); Spacer(); Text(o.type.rawValue).foregroundStyle(.secondary).font(.subheadline) }
                }
                .toggleStyle(.checkbox)
            }
            Text(L10n.tr("Zaznaczone: \(selected.count) z \(objects.count)")).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

/// Eksport obiektów użytkownika (UG 24.6, PD-TOOL-007).
struct ExportObjectsView: View {
    let workspace: Workspace
    @State private var owner = ""
    @State private var objects: [DBObject] = []
    @State private var selected: Set<DBObject> = []
    @State private var options = ObjectExportOptions()
    @State private var message = ""
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField(L10n.tr("Schemat"), text: $owner).frame(maxWidth: 220).textFieldStyle(.roundedBorder).onSubmit { Task { await load() } }
                Button(L10n.tr("Wczytaj")) { Task { await load() } }
            }
            ObjectPicker(objects: objects, selected: $selected)
            Form {
                Picker(L10n.tr("Pliki"), selection: $options.layout) {
                    Text(L10n.tr("Jeden plik")).tag(ObjectExportOptions.Layout.singleFile)
                    Text(L10n.tr("Plik na obiekt")).tag(ObjectExportOptions.Layout.filePerObject)
                }
                Toggle(L10n.tr("Specyfikacja i ciało w jednym pliku"), isOn: $options.specAndBodyTogether).disabled(options.layout == .singleFile)
                Toggle(L10n.tr("Uprawnienia"), isOn: $options.includePrivileges)
                Toggle(L10n.tr("Parametry składowania"), isOn: $options.includeStorage)
                Toggle(L10n.tr("Nazwa schematu w DDL"), isOn: $options.includeOwner)
            }
            HStack {
                Text(message).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.tr("Eksportuj…")) { Task { await export() } }.disabled(selected.isEmpty || busy)
            }
        }
        .padding(12)
        .frame(minWidth: 620, minHeight: 560)
        .task {
            owner = workspace.sessions.connectedSchema(workspace.sessions.mainConnectionID) ?? ""
            await load()
        }
    }

    private func session() async throws -> any DatabaseSession {
        try await SessionCommands.toolSession(workspace)
    }

    private func load() async {
        do {
            objects = try await ObjectExport.objects(owner: owner.uppercased(), in: try await session())
            selected = []
            message = L10n.tr("Obiekty: \(objects.count)")
        } catch { message = error.localizedDescription }
    }

    private func export() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L10n.tr("Eksportuj")
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        busy = true
        defer { busy = false }
        do {
            let files = try await ObjectExport.export(Array(selected), options: options, in: try await session()) { n in message = L10n.tr("Wyeksportowano \(n) z \(selected.count)") }
            for f in files { try Data(f.content.utf8).write(to: dir.appendingPathComponent(f.name)) }
            message = L10n.tr("Zapisano plików: \(files.count)")
        } catch { message = error.localizedDescription }
    }
}

/// Porównanie obiektów użytkowników (UG 24.11, PD-TOOL-012).
struct CompareObjectsView: View {
    let workspace: Workspace
    @State private var owner = ""
    @State private var objects: [DBObject] = []
    @State private var selected: Set<DBObject> = []
    @State private var targetID: UUID?
    @State private var targetOwner = ""
    @State private var options = CompareOptions()
    @State private var diffs: [ObjectDifference] = []
    @State private var diffSelection: ObjectDifference.ID?
    @State private var message = ""
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField(L10n.tr("Schemat źródłowy"), text: $owner).frame(maxWidth: 200).textFieldStyle(.roundedBorder).onSubmit { Task { await load() } }
                Button(L10n.tr("Wczytaj")) { Task { await load() } }
                Spacer()
                Picker(L10n.tr("Połączenie docelowe"), selection: $targetID) {
                    ForEach(workspace.connections.connections) { Text($0.displayName).tag(UUID?.some($0.id)) }
                }
                .frame(maxWidth: 300)
                TextField(L10n.tr("Schemat docelowy"), text: $targetOwner).frame(maxWidth: 180).textFieldStyle(.roundedBorder)
            }
            HSplitView {
                ObjectPicker(objects: objects, selected: $selected).frame(minWidth: 300)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Toggle(L10n.tr("Ignoruj wielkość liter"), isOn: $options.ignoreCase)
                        Toggle(L10n.tr("Ignoruj odstępy"), isOn: $options.ignoreWhitespace)
                        Toggle(L10n.tr("Składowanie"), isOn: $options.includeStorage)
                        Toggle(L10n.tr("Usuń nadmiarowe"), isOn: $options.dropExtra)
                    }
                    .toggleStyle(.checkbox).font(.subheadline)
                    Table(diffs, selection: $diffSelection) {
                        TableColumn(L10n.tr("Obiekt")) { d in Text(d.name) }
                        TableColumn(L10n.tr("Typ")) { d in Text(d.type.rawValue) }.width(110)
                        TableColumn(L10n.tr("Różnica")) { d in Text(status(d.status)) }.width(140)
                    }
                    .contextMenu(forSelectionType: ObjectDifference.ID.self) { _ in } primaryAction: { ids in
                        if let d = diffs.first(where: { ids.contains($0.id) }) { show(d) }
                    }
                }
                .frame(minWidth: 380)
            }
            HStack {
                Text(message).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.tr("Porównaj")) { Task { await compare() } }.disabled(selected.isEmpty || targetID == nil || targetOwner.isEmpty || busy)
                Button(L10n.tr("Pokaż różnice")) { if let d = diffs.first(where: { $0.id == diffSelection }) { show(d) } }.disabled(diffSelection == nil)
                Button(L10n.tr("Kopiuj SQL")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ObjectCompare.script(diffs), forType: .string)
                }.disabled(diffs.isEmpty)
                Button(L10n.tr("Otwórz SQL")) {
                    let d = workspace.newDocument(.sql, text: ObjectCompare.script(diffs))
                    d.connectionID = targetID
                }.disabled(diffs.isEmpty)
            }
        }
        .padding(12)
        .frame(minWidth: 900, minHeight: 560)
        .task {
            owner = workspace.sessions.connectedSchema(workspace.sessions.mainConnectionID) ?? ""
            targetID = workspace.sessions.mainConnectionID
            await load()
        }
    }

    private func status(_ s: ObjectDifference.Status) -> String {
        switch s {
        case .onlySource: L10n.tr("tylko w źródle")
        case .onlyTarget: L10n.tr("tylko w celu")
        case .different: L10n.tr("różny")
        }
    }

    private func load() async {
        do {
            objects = try await ObjectExport.objects(owner: owner.uppercased(), in: try await SessionCommands.toolSession(workspace))
            selected = []
            message = L10n.tr("Obiekty: \(objects.count)")
        } catch { message = error.localizedDescription }
    }

    private func compare() async {
        guard let targetID else { return }
        busy = true
        defer { busy = false }
        do {
            let target = try await workspace.sessions.session(SessionKey(connectionID: targetID, purpose: .tool("compare")))
            diffs = try await ObjectCompare.compare(Array(selected), source: try await SessionCommands.toolSession(workspace),
                                                   targetOwner: targetOwner.uppercased(), target: target, options: options) { n in
                message = L10n.tr("Porównano \(n) z \(selected.count)")
            }
            message = L10n.tr("Różnice: \(diffs.count)")
        } catch { message = error.localizedDescription }
    }

    private func show(_ d: ObjectDifference) {
        workspace.ui?.showDiff(left: d.sourceDDL, right: d.targetDDL, leftTitle: "\(owner.uppercased()).\(d.name)", rightTitle: "\(targetOwner.uppercased()).\(d.name)")
    }
}
