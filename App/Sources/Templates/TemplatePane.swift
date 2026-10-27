import AppKit
import PelikanWorkspace
import SwiftUI

/// Template Window (UG 31.1): szablony w folderach z filtrem; dwuklik albo przeciągnięcie do edytora wstawia szablon
/// (formularz zmiennych), menu kontekstowe: wstaw, nowe okno, usuń szablon użytkownika, zapisz zaznaczenie jako
/// szablon; w pasku bocznym albo w osobnym, pływającym oknie (PD-TPL-001).
struct TemplatePane: View {
    /// Przeciągany szablon (identyfikator folder/nazwa) — upuszczenie w edytorze wstawia go z formularzem (PD-TPL-002).
    static let pasteboardType = NSPasteboard.PasteboardType("local.pelikan.template")
    let workspace: Workspace
    @State private var filter = ""
    @State private var selection: String?

    private var folders: [(String, [CodeTemplate])] {
        _ = workspace.templatesGeneration
        let f = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let list = workspace.templates.all.filter { f.isEmpty || $0.name.lowercased().contains(f) || $0.folder.lowercased().contains(f) }
        var grouped = Dictionary(grouping: list, by: \.folder)
        // Puste foldery użytkownika też widoczne (PD-TPL-003), gdy filtr jest pusty.
        if f.isEmpty { for folder in workspace.templates.folders where grouped[folder] == nil { grouped[folder] = [] } }
        return grouped.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    /// Folder zaznaczenia: identyfikator folderu (`#folder:nazwa`) albo folder zaznaczonego szablonu.
    private func folder(of id: String) -> String? {
        if id.hasPrefix("#folder:") { return String(id.dropFirst("#folder:".count)) }
        return workspace.templates.template(id)?.folder
    }

    var body: some View {
        VStack(spacing: 6) {
            TextField(L10n.tr("Filtr szablonów"), text: $filter)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 8)
            List(selection: $selection) {
                ForEach(folders, id: \.0) { folder, templates in
                    Section(folder) {
                        if templates.isEmpty {
                            Text(L10n.tr("(pusty folder)")).foregroundStyle(.secondary).tag("#folder:" + folder)
                        }
                        ForEach(templates) { t in
                            Label(t.name, systemImage: t.isBuiltIn ? "doc.text" : "doc.text.fill")
                                .tag(t.id)
                                .help(t.text)
                                .onDrag { Self.dragItem(t) }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .contextMenu(forSelectionType: String.self) { ids in
                if let id = ids.first, !id.hasPrefix("#folder:"), let t = workspace.templates.template(id) {
                    Button(L10n.tr("Wstaw")) { insert(id) }
                    Button(L10n.tr("Nowe okno z szablonu")) { workspace.perform("file.newFromTemplate", CommandArguments(["template": .string(id)])) }
                    Divider()
                    Button(L10n.tr("Edytuj szablon…")) { workspace.perform("templates.edit", CommandArguments(["template": .string(id)])) }
                    if !t.isBuiltIn {
                        Button(L10n.tr("Usuń szablon")) { workspace.perform("templates.delete", CommandArguments(["template": .string(id)])) }
                    }
                }
                Divider()
                Button(L10n.tr("Nowy szablon…")) {
                    var args: [String: JSONValue] = [:]
                    if let f = ids.first.flatMap(folder(of:)) { args["folder"] = .string(f) }
                    workspace.perform("templates.edit", CommandArguments(args))
                }
                Button(L10n.tr("Zapisz zaznaczenie jako szablon…")) { workspace.perform("templates.save") }
                Divider()
                Button(L10n.tr("Nowy folder…")) { workspace.perform("templates.newFolder") }
                if let f = ids.first.flatMap(folder(of:)) {
                    Button(L10n.tr("Zmień nazwę folderu „\(f)”…")) { workspace.perform("templates.renameFolder", CommandArguments(["folder": .string(f)])) }
                    Button(L10n.tr("Usuń folder „\(f)”")) { workspace.perform("templates.deleteFolder", CommandArguments(["folder": .string(f)])) }
                }
            } primaryAction: { ids in
                if let id = ids.first, !id.hasPrefix("#folder:") { insert(id) }
            }
        }
        .padding(.bottom, 6)
    }

    /// Element przeciągania: identyfikator szablonu i — dla celów spoza edytora — jego tekst.
    static func dragItem(_ t: CodeTemplate) -> NSItemProvider {
        let p = NSItemProvider(object: t.text as NSString)
        let id = Data(t.id.utf8)
        p.registerDataRepresentation(forTypeIdentifier: pasteboardType.rawValue, visibility: .ownProcess) { done in
            done(id, nil)
            return nil
        }
        return p
    }

    private func insert(_ id: String) {
        workspace.perform("edit.insertTemplate", CommandArguments(["template": .string(id)]))
    }
}

final class TemplatePaneController: NSViewController {
    private let workspace: Workspace
    init(workspace: Workspace) {
        self.workspace = workspace
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() { view = NSHostingView(rootView: TemplatePane(workspace: workspace).interfaceFont()) }
}
